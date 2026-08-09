import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/domain/server_profile.dart';
import '../../queue/queue.dart';
import '../../sessions/sessions.dart';
import '../data/chat_repository.dart';
import '../data/attachment_picker.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/conversation_message.dart';
import '../domain/conversation_state.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import '../domain/prompt_attachment.dart';
import '../domain/session_artifacts.dart';
import '../domain/session_execution_state.dart';

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
    required this._sessionsRepository,
    required this._queueRepositoryProvider,
    required this._queueCoordinatorProvider,
    required this._attachmentPicker,
  });

  final ChatRepository _chatRepository;
  final SessionsRepository _sessionsRepository;
  final Future<QueuePromptsRepository> Function() _queueRepositoryProvider;
  final Future<QueueSendCoordinator> Function() _queueCoordinatorProvider;
  final AttachmentPicker _attachmentPicker;

  QueuePromptsRepository? _queueRepository;
  QueueSendCoordinator? _queueCoordinator;

  /// The read-only message transcript, refreshed by [open] and [reload].
  final ValueNotifier<ConversationUiState> messages = ValueNotifier(
    const ConversationLoading(),
  );

  /// The session's todos and file diffs, fetched on open and on demand.
  final ValueNotifier<SessionArtifactsState> artifacts = ValueNotifier(
    const SessionArtifactsLoading(),
  );

  /// The active session's durable queue, in dispatch order.
  final ValueNotifier<List<QueuedPrompt>> queue = ValueNotifier(
    const <QueuedPrompt>[],
  );

  /// Memory-only files selected for the active composer. They never enter the
  /// durable prompt queue because OpenCode currently offers no upload or
  /// durable file-reference protocol.
  final ValueNotifier<List<PromptAttachment>> attachments = ValueNotifier(
    const <PromptAttachment>[],
  );

  /// The active session's pending permission or question, for a
  /// non-dismissible approval dock/sheet to render. `null` whenever
  /// nothing needs a human decision. Mirrors
  /// [QueueSendCoordinator.currentPendingApproval]; see `pending_approval.
  /// dart` for why this must never be logged or persisted. Cleared in
  /// [leave] and [dispose] for the same reason [_liveConversationState]
  /// is.
  final ValueNotifier<PendingApproval?> pendingApproval = ValueNotifier(null);

  /// The active session's live SSE connection status, mirrored from
  /// [QueueSendCoordinator.connectionState] so the conversation UI can
  /// show a connection/reconnecting indicator without reaching past this
  /// view model into the coordinator itself.
  final ValueNotifier<SseConnectionState> connectionState = ValueNotifier(
    const SseSuspended(),
  );

  /// Whether a reconciliation is running over an already-visible transcript,
  /// so the UI can float a progress indicator instead of replacing it.
  final ValueNotifier<bool> refreshing = ValueNotifier(false);

  final StreamController<String> _queueErrors =
      StreamController<String>.broadcast();

  final StreamController<String> _transcriptErrors =
      StreamController<String>.broadcast();

  /// User-facing messages for a refresh that failed while a transcript was
  /// already visible; the visible transcript is kept as-is.
  Stream<String> get transcriptErrors => _transcriptErrors.stream;

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
  Timer? _liveRenderTimer;
  ConversationState? _pendingLiveRender;

  /// The open session's live connection status, as exposed by
  /// [QueueSendCoordinator.connectionState]. Cleared in [leave] and
  /// [dispose] for the same reason as [_liveConversationState].
  ValueListenable<SseConnectionState>? _remoteConnectionState;
  VoidCallback? _remoteConnectionStateListener;
  SessionExecutionState? _lastSessionExecutionState;

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

    // Rendering the server transcript is the first useful result of opening a
    // conversation. Start coordination concurrently, but never make it delay
    // the initial transcript frame.
    final activation = queueCoordinator.activate(
      profile: profile,
      session: session,
    );
    await _loadMessages();
    await activation;
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
      _scheduleLiveConversationRender(liveConversationState.value);
      pendingApproval.value =
          liveConversationState.value.pendingApprovals[session.id];
      final nextState = liveConversationState.value.sessionStates[session.id];
      if (nextState is SessionIdle &&
          _lastSessionExecutionState is! SessionIdle) {
        unawaited(_loadArtifacts());
      }
      _lastSessionExecutionState = nextState;
    }

    _liveConversationState = liveConversationState;
    _liveConversationStateListener = onLiveConversationStateChanged;
    liveConversationState.addListener(onLiveConversationStateChanged);
    // `activate` may have already reduced a block (and its detail) before
    // this listener was attached; pick that up now rather than waiting
    // for the next SSE event to change it.
    _scheduleLiveConversationRender(liveConversationState.value);
    pendingApproval.value = queueCoordinator.currentPendingApproval;
    _lastSessionExecutionState = queueCoordinator.currentSessionState;

    // Mirrors the coordinator's connection status so the conversation UI
    // can render it, and — the moment a reconnect starts reconciling —
    // re-fetches the transcript over REST rather than trusting whatever
    // the live state accumulated across the drop. Queue dispatch is
    // separately held by the coordinator itself for the same window; see
    // `QueueSendCoordinator._maybeDispatch`.
    final remoteConnectionState = queueCoordinator.connectionState;
    void onRemoteConnectionStateChanged() {
      if (_disposed || _session != session) {
        return;
      }
      final next = remoteConnectionState.value;
      connectionState.value = next;
      if (next is SseReconciling) {
        unawaited(_loadMessages());
      }
    }

    _remoteConnectionState = remoteConnectionState;
    _remoteConnectionStateListener = onRemoteConnectionStateChanged;
    remoteConnectionState.addListener(onRemoteConnectionStateChanged);
    connectionState.value = remoteConnectionState.value;

    // Artifacts enrich the conversation but must never delay its first frame.
    unawaited(_loadArtifacts());
  }

  /// Re-fetches the transcript for the currently open session.
  Future<void> reload() => _loadMessages();

  /// Reconciles every server-owned conversation surface from a direct user
  /// gesture without affecting the local send queue.
  Future<void> refreshFromUserAction() =>
      Future.wait([_loadMessages(), _loadArtifacts()]);

  /// Re-fetches todos and the session diff. [messageId] narrows the diff to
  /// the point OpenCode associates with that message when supplied.
  Future<void> reloadArtifacts({String? messageId}) =>
      _loadArtifacts(messageId: messageId);

  Future<SessionCreateResult?> fork() {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return Future.value(null);
    }
    return _sessionsRepository.fork(profile, session);
  }

  Future<SessionShareResult?> share() {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return Future.value(null);
    }
    return _sessionsRepository.share(profile, session);
  }

  Future<SessionsFailure?> unshare() async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return SessionsFailure.unexpectedResponse;
    }
    final result = await _sessionsRepository.unshare(profile, session);
    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
  }

  Future<SessionsFailure?> revert(String messageId) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null || messageId.isEmpty) {
      return SessionsFailure.unexpectedResponse;
    }
    final result = await _sessionsRepository.revert(
      profile,
      session,
      messageId,
    );
    return switch (result) {
      Ok(:final value) when value => await _refreshAfterRevert(messageId),
      Ok() => SessionsFailure.unexpectedResponse,
      Err(:final failure) => failure,
    };
  }

  Future<SessionsFailure?> _refreshAfterRevert(String messageId) async {
    await Future.wait([_loadMessages(), _loadArtifacts(messageId: messageId)]);
    return null;
  }

  void retryConnection() => _queueCoordinator?.retryConnection();

  Future<void> _loadMessages() async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return;
    }
    // Reloading an already-visible transcript keeps it on screen and only
    // reports progress, so the reader never loses their place — and the whole
    // transcript is not rebuilt from an empty state.
    final hadTranscript = messages.value is ConversationReady;
    if (hadTranscript) {
      refreshing.value = true;
    } else {
      messages.value = const ConversationLoading();
    }
    final result = await _chatRepository.load(profile, session);
    if (_disposed || _session != session) {
      return;
    }
    refreshing.value = false;
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
        // A failed refresh must not discard a readable transcript.
        if (hadTranscript) {
          _transcriptErrors.add(failure.message);
        } else {
          messages.value = ConversationError(failure);
        }
    }
  }

  Future<void> _loadArtifacts({String? messageId}) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return;
    }
    artifacts.value = const SessionArtifactsLoading();
    final result = await _chatRepository.loadArtifacts(
      profile,
      session,
      messageId: messageId,
    );
    if (_disposed || _session != session) {
      return;
    }
    artifacts.value = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => SessionArtifactsError(failure),
    };
  }

  /// Merges [liveState] — the active session's live conversation, reduced
  /// from SSE `message.updated`/`message.part.updated` events — onto the
  /// currently visible transcript.
  ///
  /// Rendering is scheduled in small batches by
  /// [_scheduleLiveConversationRender], rather than once per SSE event.
  /// `message.removed`/`message.part.removed` are reduced by
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

  /// Coalesces bursty token/tool events into a visual update every 60ms. The
  /// coordinator still reduces each event immediately, so queue safety and
  /// approval handling are never delayed by this display optimisation.
  void _scheduleLiveConversationRender(ConversationState liveState) {
    _pendingLiveRender = liveState;
    if (_liveRenderTimer != null) {
      return;
    }
    _liveRenderTimer = Timer(const Duration(milliseconds: 60), () {
      _liveRenderTimer = null;
      final pending = _pendingLiveRender;
      _pendingLiveRender = null;
      if (pending != null && !_disposed && _session != null) {
        _applyLiveConversationState(pending);
      }
    });
  }

  /// Durably enqueues [text] for the open session. Never sends directly:
  /// dispatch timing is entirely owned by [QueueSendCoordinator].
  Future<bool> enqueuePrompt(
    String text, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    // The composer's selection is copied into the durable queue record, so
    // the memory-only buffers can be released as soon as it is stored.
    final selected = attachments.value;
    final queuedAttachments = [
      for (final attachment in selected)
        QueuedAttachment(
          name: attachment.name,
          mediaType: attachment.mediaType,
          bytes: Uint8List.fromList(attachment.bytes),
        ),
    ];
    final profile = _profile;
    final session = _session;
    final queueRepository = _queueRepository;
    if (profile == null || session == null || queueRepository == null) {
      return false;
    }
    final result = await queueRepository.enqueue(
      profile: profile,
      session: session,
      promptText: text,
      attachments: queuedAttachments,
      executionOptions: executionOptions,
    );
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    releaseAttachments();
    return true;
  }

  /// Appends a queued prompt's text to the prompt directly above it and
  /// removes it, so both are delivered as a single turn instead of two
  /// separate deferred sends. Only plain prompts that are still editable can
  /// be merged; commands and in-flight prompts are rejected with a message.
  Future<void> mergeIntoPrevious(String promptId) async {
    final repository = _queueRepository;
    if (repository == null) {
      return;
    }
    final prompts = queue.value
        .where((prompt) => prompt.state != QueuedPromptState.acknowledged)
        .toList(growable: false);
    final index = prompts.indexWhere((prompt) => prompt.id == promptId);
    if (index <= 0) {
      _queueErrors.add('There is no earlier prompt to merge this one into.');
      return;
    }
    final source = prompts[index];
    final target = prompts[index - 1];
    if (!_canMerge(source) || !_canMerge(target)) {
      _queueErrors.add('Only queued prompts can be merged.');
      return;
    }
    if (source.attachments.isNotEmpty) {
      _queueErrors.add('Remove this prompt\'s attachments before merging it.');
      return;
    }
    final edited = await repository.edit(
      promptId: target.id,
      promptText: '${target.promptText}\n\n${source.promptText}',
    );
    if (edited case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return;
    }
    final removed = await repository.remove(source.id);
    if (removed case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  bool _canMerge(QueuedPrompt prompt) {
    return prompt.operationType == QueuedOperationType.prompt &&
        (prompt.state == QueuedPromptState.queued ||
            prompt.state == QueuedPromptState.paused ||
            prompt.state == QueuedPromptState.failed);
  }

  /// Invoked only by the composer's explicit attachment control.
  Future<AttachmentPickResult> pickAttachments() async {
    if (_disposed) {
      return const AttachmentPickCancelled();
    }
    final result = await _attachmentPicker.pick();
    if (_disposed) {
      if (result case AttachmentsPicked(:final attachments)) {
        _releaseAttachments(attachments);
      }
      return const AttachmentPickCancelled();
    }
    if (result case AttachmentsPicked(:final attachments)) {
      final current = this.attachments.value;
      final combinedCount = current.length + attachments.length;
      final combinedBytes =
          current.fold<int>(
            0,
            (total, attachment) => total + attachment.byteCount,
          ) +
          attachments.fold<int>(
            0,
            (total, attachment) => total + attachment.byteCount,
          );
      if (combinedCount > PromptAttachment.maxAttachmentCount ||
          combinedBytes > PromptAttachment.maxTotalBytes) {
        _releaseAttachments(attachments);
        return const AttachmentPickRejected(
          'Keep up to 5 attachments totaling 25 MiB or less.',
        );
      }
      this.attachments.value = [...current, ...attachments];
    }
    return result;
  }

  void removeAttachment(PromptAttachment attachment) {
    final current = attachments.value;
    if (!current.contains(attachment)) {
      return;
    }
    attachment.release();
    attachments.value = current
        .where((candidate) => !identical(candidate, attachment))
        .toList(growable: false);
  }

  /// Discards every memory-only attachment. Called after a cancelled or
  /// rejected attached submission, on lifecycle inactivity, and on teardown.
  void releaseAttachments() {
    _releaseAttachments(attachments.value);
    attachments.value = const <PromptAttachment>[];
  }

  /// Durably enqueues a slash command. Commands share the prompt queue so a
  /// busy session never loses or implicitly aborts active work.
  Future<bool> enqueueCommand(
    String commandName,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    final profile = _profile;
    final session = _session;
    final queueRepository = _queueRepository;
    if (profile == null || session == null || queueRepository == null) {
      return false;
    }
    final result = await queueRepository.enqueueCommand(
      profile: profile,
      session: session,
      commandName: commandName,
      arguments: arguments,
      executionOptions: executionOptions,
    );
    if (result case Err<QueuedPrompt, QueueFailure>(:final failure)) {
      _queueErrors.add(failure.message);
      return false;
    }
    return true;
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

  /// Responds to the open session's pending tool-call permission with
  /// [response]. See [QueueSendCoordinator.respondToPermission].
  Future<void> respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return;
    }
    final result = await queueCoordinator.respondToPermission(
      permissionId,
      response,
    );
    if (result case Err<void, QueueApprovalFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Answers the open session's pending question request with [answers].
  /// See [QueueSendCoordinator.replyToQuestion].
  Future<void> replyToQuestion(
    String requestId,
    List<List<String>> answers,
  ) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return;
    }
    final result = await queueCoordinator.replyToQuestion(requestId, answers);
    if (result case Err<void, QueueApprovalFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Rejects the open session's pending question request outright. See
  /// [QueueSendCoordinator.rejectQuestion].
  Future<void> rejectQuestion(String requestId) async {
    final queueCoordinator = _queueCoordinator;
    if (queueCoordinator == null) {
      return;
    }
    final result = await queueCoordinator.rejectQuestion(requestId);
    if (result case Err<void, QueueApprovalFailure>(:final failure)) {
      _queueErrors.add(failure.message);
    }
  }

  /// Deactivates queue coordination and stops watching the queue for the
  /// currently open session, if any. Safe to call repeatedly, including
  /// before the queue has ever been opened. Called when the conversation
  /// screen leaves the active session, and internally by [open] before
  /// switching to a different one.
  Future<void> leave() async {
    _liveRenderTimer?.cancel();
    _liveRenderTimer = null;
    _pendingLiveRender = null;
    releaseAttachments();
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    _detachLiveConversationState();
    _detachRemoteConnectionState();
    await _queueCoordinator?.deactivate();
    connectionState.value = const SseSuspended();
    pendingApproval.value = null;
    artifacts.value = const SessionArtifactsLoading();
    _profile = null;
    _session = null;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _liveRenderTimer?.cancel();
    _liveRenderTimer = null;
    _pendingLiveRender = null;
    releaseAttachments();
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    _detachLiveConversationState();
    _detachRemoteConnectionState();
    await _queueCoordinator?.deactivate();
    messages.dispose();
    artifacts.dispose();
    queue.dispose();
    attachments.dispose();
    connectionState.dispose();
    pendingApproval.dispose();
    refreshing.dispose();
    unawaited(_queueErrors.close());
    unawaited(_transcriptErrors.close());
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

  void _detachRemoteConnectionState() {
    final remoteConnectionState = _remoteConnectionState;
    final listener = _remoteConnectionStateListener;
    if (remoteConnectionState != null && listener != null) {
      remoteConnectionState.removeListener(listener);
    }
    _remoteConnectionState = null;
    _remoteConnectionStateListener = null;
    _lastSessionExecutionState = null;
  }
}

void _releaseAttachments(Iterable<PromptAttachment> attachments) {
  for (final attachment in attachments) {
    attachment.release();
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
    final text = _renderTextParts(liveMessage.parts) ?? '';
    final existing = byId[liveMessage.id];
    // Live tool events carry only a short summary, never the tool's output.
    // Merging them over the REST detail would blank an already-loaded body.
    final details = _keepLoadedDetailBodies(
      _renderLiveDetails(liveMessage.parts),
      existing?.details ?? const <ChatMessageDetail>[],
    );
    // A task/tool may arrive before the assistant writes prose. Keep that
    // message in the transcript so its live progress is never invisible.
    if (text.isEmpty && details.isEmpty) {
      continue;
    }
    final mergedText = existing != null && existing.text.startsWith(text)
        ? existing.text
        : text;
    final mergedDetails = details.isEmpty
        ? existing?.details ?? const []
        : details;
    if (existing != null &&
        existing.role == role &&
        existing.text == mergedText &&
        _sameDetails(existing.details, mergedDetails)) {
      continue;
    }
    if (existing == null) {
      order.add(liveMessage.id);
    }
    byId[liveMessage.id] = ChatMessage(
      id: liveMessage.id,
      role: role,
      createdAt: existing?.createdAt ?? DateTime.now(),
      text: mergedText,
      details: mergedDetails,
      error: existing?.error,
    );
    changed = true;
  }

  if (!changed) {
    return restMessages;
  }
  return [for (final id in order) byId[id]!];
}

List<ChatMessageDetail> _renderLiveDetails(List<MessagePart> parts) {
  return [
    for (final part in parts)
      switch (part) {
        ReasoningMessagePart(:final id, :final text) => ChatReasoningDetail(
          id: id,
          text: text,
        ),
        ToolMessagePart(
          :final id,
          :final tool,
          :final status,
          :final summary,
          :final error,
        ) =>
          ChatToolDetail(
            id: id,
            tool: tool,
            status: status.name,
            input: summary,
            error: error,
          ),
        _ => null,
      },
  ].whereType<ChatMessageDetail>().toList(growable: false);
}

/// Returns [live] with any tool body already loaded over REST preserved.
///
/// `message.part.updated` reports a tool's identity, status, and a short
/// input summary, but never its output or reasoning body. Without this, a
/// later live status change would replace a fully loaded tool card with an
/// empty one.
List<ChatMessageDetail> _keepLoadedDetailBodies(
  List<ChatMessageDetail> live,
  List<ChatMessageDetail> loaded,
) {
  if (loaded.isEmpty || live.isEmpty) {
    return live;
  }
  final loadedById = {for (final detail in loaded) detail.id: detail};
  return [
    for (final detail in live)
      if (detail is ChatToolDetail)
        switch (loadedById[detail.id]) {
          final ChatToolDetail prior => ChatToolDetail(
            id: detail.id,
            tool: detail.tool,
            status: detail.status,
            input: detail.input ?? prior.input,
            output: detail.output ?? prior.output,
            error: detail.error ?? prior.error,
          ),
          _ => detail,
        }
      else if (detail is ChatReasoningDetail && detail.text.isEmpty)
        switch (loadedById[detail.id]) {
          final ChatReasoningDetail prior => prior,
          _ => detail,
        }
      else
        detail,
  ];
}

bool _sameDetails(List<ChatMessageDetail> left, List<ChatMessageDetail> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    final a = left[i];
    final b = right[i];
    if (a.runtimeType != b.runtimeType || a.id != b.id) {
      return false;
    }
    if (a is ChatReasoningDetail && b is ChatReasoningDetail) {
      if (a.text != b.text) {
        return false;
      }
    } else if (a is ChatToolDetail && b is ChatToolDetail) {
      if (a.tool != b.tool ||
          a.status != b.status ||
          a.input != b.input ||
          a.output != b.output ||
          a.error != b.error) {
        return false;
      }
    }
  }
  return true;
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
