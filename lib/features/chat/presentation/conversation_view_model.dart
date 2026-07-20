import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/domain/server_profile.dart';
import '../../queue/queue.dart';
import '../../sessions/domain/open_code_session.dart';
import '../data/chat_repository.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/conversation_message.dart';
import '../domain/conversation_state.dart';

sealed class ConversationUiState {
  const ConversationUiState();
}

class ConversationLoading extends ConversationUiState {
  const ConversationLoading();
}

class ConversationReady extends ConversationUiState {
  const ConversationReady(this.messages);

  final List<ChatMessage> messages;
}

class ConversationError extends ConversationUiState {
  const ConversationError(this.failure);

  final ChatFailure failure;
}

/// Drives one conversation screen: the read-only message transcript (via
/// [ChatRepository]) and the durable per-session send queue (via
/// [QueuePromptsRepository] and [QueueSendCoordinator]).
///
/// Every prompt the composer submits is durably enqueued first; this view
/// model never calls [ChatRepository.sendPrompt] directly, so a send is
/// always subject to the queue's dispatch and abort rules. Queue action
/// failures are reported on [queueErrors] rather than held as persistent
/// state, since they describe a single rejected command, not the queue's
/// current shape.
///
/// [queueRepositoryProvider] and [queueCoordinatorProvider] are resolved
/// lazily, on the first call to [open], rather than eagerly at construction.
/// The queue's storage opens a real database connection (a background
/// isolate and platform file lookup), which this view model's owner should
/// not pay for before a conversation is actually opened.
class ConversationViewModel {
  ConversationViewModel({
    required this._chatRepository,
    required this._queueRepositoryProvider,
    required this._queueCoordinatorProvider,
  });

  final ChatRepository _chatRepository;
  final Future<QueuePromptsRepository> Function() _queueRepositoryProvider;
  final Future<QueueSendCoordinator> Function() _queueCoordinatorProvider;

  QueuePromptsRepository? _queueRepository;
  QueueSendCoordinator? _queueCoordinator;

  /// The read-only message transcript, refreshed by [open] and [reload].
  final ValueNotifier<ConversationUiState> messages = ValueNotifier(
    const ConversationLoading(),
  );

  /// The active session's durable queue, in dispatch order.
  final ValueNotifier<List<QueuedPrompt>> queue = ValueNotifier(
    const <QueuedPrompt>[],
  );

  final StreamController<String> _queueErrors =
      StreamController<String>.broadcast();

  /// User-facing messages for a rejected queue command (enqueue, remove, or
  /// send now). Each event describes one rejected command; it is not
  /// retained as state.
  Stream<String> get queueErrors => _queueErrors.stream;

  ServerProfile? _profile;
  OpenCodeSession? _session;
  StreamSubscription<List<QueuedPrompt>>? _queueSubscription;

  /// The open session's live conversation state, as exposed by
  /// [QueueSendCoordinator.conversationStateUpdates]. Cleared in [leave]
  /// and [dispose] so a rebuild from a session this view model has since
  /// left can never reach [_applyLiveConversationState].
  ValueListenable<ConversationState>? _liveConversationState;
  VoidCallback? _liveConversationStateListener;

  bool _disposed = false;

  /// Loads [session]'s transcript, activates queue coordination for it, and
  /// starts watching its durable queue. Tears down any previously open
  /// session first, mirroring [QueueSendCoordinator]'s single-active-session
  /// rule.
  Future<void> open(ServerProfile profile, OpenCodeSession session) async {
    await leave();
    if (_disposed) {
      return;
    }
    _profile = profile;
    _session = session;

    final queueRepository = _queueRepository ??=
        await _queueRepositoryProvider();
    final queueCoordinator = _queueCoordinator ??=
        await _queueCoordinatorProvider();
    if (_disposed || _session != session) {
      return;
    }

    _queueSubscription = queueRepository
        .watchQueue(profile: profile, session: session)
        .listen((rows) {
          if (_disposed) {
            return;
          }
          queue.value = rows;
        });

    await queueCoordinator.activate(profile: profile, session: session);
    if (_disposed || _session != session) {
      return;
    }

    // Subscribed before the REST load below so no live event is ever
    // missed while it is in flight; any event reduced during that window
    // is still reconciled from the coordinator's authoritative snapshot
    // once the load finishes (see `_loadMessages`).
    final liveConversationState = queueCoordinator.conversationStateUpdates;
    void onLiveConversationStateChanged() {
      if (_disposed || _session != session) {
        // This session is no longer the one open in this view model
        // (left, or superseded by a faster-finishing `open` for another
        // session); never apply its live state to the visible transcript.
        return;
      }
      _applyLiveConversationState(liveConversationState.value);
    }

    _liveConversationState = liveConversationState;
    _liveConversationStateListener = onLiveConversationStateChanged;
    liveConversationState.addListener(onLiveConversationStateChanged);

    await _loadMessages();
  }

  /// Re-fetches the transcript for the currently open session.
  Future<void> reload() => _loadMessages();

  Future<void> _loadMessages() async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return;
    }
    messages.value = const ConversationLoading();
    final result = await _chatRepository.load(profile, session);
    if (_disposed) {
      return;
    }
    switch (result) {
      case ChatLoaded(messages: final loadedMessages):
        messages.value = ConversationReady(loadedMessages);
        // Reconciles against whatever the live conversation state has
        // already accumulated for this session (including any event
        // reduced while this REST load was in flight), rather than
        // waiting for the next SSE event to reveal it.
        final liveState = _liveConversationState?.value;
        if (liveState != null) {
          _applyLiveConversationState(liveState);
        }
      case ChatLoadFailed(:final failure):
        messages.value = ConversationError(failure);
    }
  }

  /// Merges [liveState] — the active session's live conversation, reduced
  /// from SSE `message.updated`/`message.part.updated` events — onto the
  /// currently visible transcript.
  ///
  /// Only messages [liveState] has actually rendered text for are merged:
  /// this never overwrites an already-loaded REST message with a blank
  /// transcript before its own SSE events have caught up, and never shows
  /// an empty placeholder bubble before a new message's first text part
  /// arrives. `message.removed`/`message.part.removed` are reduced by
  /// `conversation_state.dart` but intentionally not reflected here; a
  /// removal is reconciled by the next REST [reload], consistent with this
  /// app's reconnect-then-REST-reconcile rule for the transcript.
  void _applyLiveConversationState(ConversationState liveState) {
    final current = messages.value;
    if (current is! ConversationReady) {
      // Still loading, or the previous load failed; nothing to merge onto
      // yet. `_loadMessages` reconciles against the coordinator's current
      // snapshot itself once it reaches `ConversationReady`.
      return;
    }
    final merged = _mergeLiveConversationState(current.messages, liveState);
    if (!identical(merged, current.messages)) {
      messages.value = ConversationReady(merged);
    }
  }

  /// Durably enqueues [text] for the open session. Never sends directly:
  /// dispatch timing is entirely owned by [QueueSendCoordinator].
  Future<void> enqueuePrompt(String text) async {
    final profile = _profile;
    final session = _session;
    final queueRepository = _queueRepository;
    if (profile == null || session == null || queueRepository == null) {
      return;
    }
    final result = await queueRepository.enqueue(
      profile: profile,
      session: session,
      promptText: text,
    );
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Removes a queued prompt. Rejected by the repository while the prompt
  /// is currently `sending`.
  Future<void> removeFromQueue(String promptId) async {
    final queueRepository = _queueRepository;
    if (queueRepository == null) {
      return;
    }
    final result = await queueRepository.remove(promptId);
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Explicitly aborts the active generation, then dispatches [promptId]
  /// ahead of the queue head once the session settles idle. The caller is
  /// responsible for confirming this action with the user before calling
  /// it, since it cancels in-progress work.
  Future<void> sendNow(String promptId) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return;
    }
    final result = await queueCoordinator.sendNow(promptId);
    if (result case Err<void, QueueSendNowFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Deactivates queue coordination and stops watching the queue for the
  /// currently open session, if any. Safe to call repeatedly, including
  /// before the queue has ever been opened. Called when the conversation
  /// screen leaves the active session, and internally by [open] before
  /// switching to a different one.
  Future<void> leave() async {
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    _detachLiveConversationState();
    await _queueCoordinator?.deactivate();
    _profile = null;
    _session = null;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    _detachLiveConversationState();
    await _queueCoordinator?.deactivate();
    messages.dispose();
    queue.dispose();
    unawaited(_queueErrors.close());
  }

  void _detachLiveConversationState() {
    final liveConversationState = _liveConversationState;
    final listener = _liveConversationStateListener;
    if (liveConversationState != null && listener != null) {
      liveConversationState.removeListener(listener);
    }
    _liveConversationState = null;
    _liveConversationStateListener = null;
  }
}

/// Merges [liveState] onto [restMessages], preserving [restMessages]'
/// order and reusing its unchanged entries by reference (so an unaffected
/// row's [ChatMessage] instance is unchanged, not merely equal) — this
/// lets a display layer that memoizes per-row widgets on message identity
/// rebuild only the rows a live update actually changed. A message with no
/// rendered text yet is skipped entirely; see [_applyLiveConversationState]
/// for why.
///
/// Returns [restMessages] itself, unchanged, if nothing in [liveState]
/// changes the visible transcript.
List<ChatMessage> _mergeLiveConversationState(
  List<ChatMessage> restMessages,
  ConversationState liveState,
) {
  if (liveState.messages.isEmpty) {
    return restMessages;
  }

  final byId = <String, ChatMessage>{
    for (final message in restMessages) message.id: message,
  };
  final order = restMessages.map((message) => message.id).toList();
  var changed = false;

  for (final liveMessage in liveState.orderedMessages) {
    final role = switch (liveMessage.role) {
      ConversationRole.user => ChatMessageRole.user,
      ConversationRole.assistant => ChatMessageRole.assistant,
      // No `message.updated` observed yet for this id in this session;
      // nothing displayable.
      ConversationRole.unknown => null,
    };
    if (role == null) {
      continue;
    }
    final text = _renderTextParts(liveMessage.parts);
    if (text == null) {
      continue;
    }
    final existing = byId[liveMessage.id];
    if (existing != null && existing.role == role && existing.text == text) {
      continue;
    }
    if (existing == null) {
      order.add(liveMessage.id);
    }
    byId[liveMessage.id] = ChatMessage(
      id: liveMessage.id,
      role: role,
      createdAt: existing?.createdAt ?? DateTime.now(),
      text: text,
    );
    changed = true;
  }

  if (!changed) {
    return restMessages;
  }
  return [for (final id in order) byId[id]!];
}

/// Concatenates every [TextMessagePart] in [parts], in order. Returns
/// `null` if [parts] carries no rendered text yet (for example a message
/// whose only parts so far are a tool call or a step marker), so a caller
/// never confuses "nothing to show yet" with an intentionally empty
/// message.
String? _renderTextParts(List<MessagePart> parts) {
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is TextMessagePart) {
      buffer.write(part.text);
    }
  }
  return buffer.isEmpty ? null : buffer.toString();
}
