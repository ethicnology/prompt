/// Orchestrates when Prompt's durable per-session queue may dispatch a
/// prompt to OpenCode.
///
/// This is deliberately a use case, not a repository: it composes
/// [QueuePromptsRepository] (the durable queue), [ChatRepository]
/// (`sendPrompt`/`abortSession`/`sessionStatus`), [OpenCodeEventService]
/// (the live SSE feed), and the pure conversation reducer. No individual
/// repository owns this coordination on its own.
///
/// Rules this type enforces:
/// - Exactly one session is coordinated at a time ("one active session
///   scope"); activating a new session tears down the previous one first.
/// - A `sending` prompt found persisted at activation is reconciled to
///   `paused`/`submissionUnknown` before anything else happens, because a
///   prior send's outcome is unknown after a restart or reactivation.
/// - The queue head only dispatches once the session's authoritative
///   status is idle and no prompt in the session is paused with
///   `submissionUnknown`; a normal enqueue never triggers an abort.
/// - `sendNow` explicitly aborts the active generation, then waits for the
///   session to settle idle before dispatching the chosen prompt.
/// - A `prompt_async` success (`204`) is definitive acceptance and marks the
///   prompt `acknowledged`; any other outcome is transport-uncertain and
///   moves the prompt to `paused`/`submissionUnknown` instead of retrying.
/// - Unrelated SSE events are ignored; only session status/idle updates
///   gate the queue.
/// - Nothing here logs prompt text or raw failure detail.
library;

import 'dart:async';

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_event_service.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/domain/chat_load_result.dart';
import '../../chat/domain/conversation_event.dart';
import '../../chat/domain/conversation_state.dart';
import '../../chat/domain/session_execution_state.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/queue_failure.dart';
import '../domain/queue_send_now_failure.dart';
import '../domain/queued_prompt.dart';
import 'queue_prompts_repository.dart';

class QueueSendCoordinator {
  QueueSendCoordinator({
    required this._queueRepository,
    required this._chatRepository,
    required this._eventService,
    required this._credentialsStore,
  });

  final QueuePromptsRepository _queueRepository;
  final ChatRepository _chatRepository;
  final OpenCodeEventService _eventService;
  final CredentialsStore _credentialsStore;

  ServerProfile? _profile;
  OpenCodeSession? _session;

  StreamSubscription<List<QueuedPrompt>>? _queueSubscription;
  StreamSubscription<OpenCodeEventEnvelope>? _sseSubscription;

  List<QueuedPrompt> _queue = const <QueuedPrompt>[];
  ConversationState _conversationState = const ConversationState();

  bool _dispatchInProgress = false;
  String? _pendingSendNowPromptId;

  /// Bumped by every [activate] and [deactivate] call. Any pending
  /// continuation that captured an earlier value is stale and must not
  /// mutate state or trigger a dispatch.
  int _activationToken = 0;

  bool _disposed = false;

  /// Whether a session is currently activated.
  bool get hasActiveSession => _profile != null && _session != null;

  /// The active session's authoritative execution state, or `null` before
  /// the first status is known.
  SessionExecutionState? get currentSessionState {
    final session = _session;
    if (session == null) {
      return null;
    }
    return _conversationState.sessionStates[session.id];
  }

  /// Activates queue coordination for [session] on [profile], tearing down
  /// any previously active session first.
  ///
  /// In order:
  /// 1. Reconciles any persisted `sending` prompt in this session's queue
  ///    to `paused`/`submissionUnknown`.
  /// 2. Fetches the session's authoritative execution state over REST.
  /// 3. Subscribes to the durable queue and to the live SSE feed, gating
  ///    automatic dispatch on both from then on.
  Future<void> activate({
    required ServerProfile profile,
    required OpenCodeSession session,
  }) async {
    _requireNotDisposed();
    await deactivate();

    _activationToken++;
    final token = _activationToken;
    _profile = profile;
    _session = session;

    final initialQueue = await _queueRepository
        .watchQueue(profile: profile, session: session)
        .first;
    if (_isStale(token)) {
      return;
    }
    _queue = initialQueue;

    for (final prompt in initialQueue) {
      if (prompt.state == QueuedPromptState.sending) {
        await _queueRepository.markSubmissionUnknown(prompt.id);
        if (_isStale(token)) {
          return;
        }
      }
    }

    final statusResult = await _chatRepository.sessionStatus(profile, session);
    if (_isStale(token)) {
      return;
    }
    if (statusResult case Ok<SessionExecutionState, ChatFailure>(
      value: final state,
    )) {
      _applySessionState(session.id, state);
    }

    _queueSubscription = _queueRepository
        .watchQueue(profile: profile, session: session)
        .listen((rows) {
          if (_isStale(token)) {
            return;
          }
          _queue = rows;
          _maybeDispatch();
        });

    final password = await _credentialsStore.readPassword(profile.id);
    if (_isStale(token)) {
      return;
    }
    _sseSubscription = _eventService
        .connect(profile, password)
        .listen(
          (envelope) {
            if (_isStale(token)) {
              return;
            }
            final event = mapConversationEvent(
              envelope,
              sessionId: session.id,
              directory: session.directory,
            );
            if (event == null) {
              // Unrelated event (other session/directory, unmodeled type,
              // or malformed payload): ignored, never gates the queue.
              return;
            }
            _conversationState = reduceConversationEvent(
              _conversationState,
              event,
            );
            _maybeDispatch();
          },
          onError: (Object _) {
            // A dropped SSE connection never crashes coordination and
            // never triggers a retry by itself; the next activation
            // reconciles authoritative state instead.
          },
        );

    _maybeDispatch();
  }

  /// Tears down the active session scope: cancels the SSE subscription and
  /// the queue watch, and drops in-memory state. Safe to call when nothing
  /// is active. Does not change any persisted queue row; a prompt left
  /// `sending` here is reconciled the next time its session is activated.
  Future<void> deactivate() async {
    _activationToken++;
    await _queueSubscription?.cancel();
    _queueSubscription = null;
    // Not awaited: an `async*`/`await for` SSE decoder paused between
    // events only processes a downstream cancellation once it resumes
    // (the next event, or the connection closing), so awaiting this could
    // block deactivation indefinitely on an idle connection. The token
    // bump above already makes every later callback from this
    // subscription a no-op, so dropping the future here is safe.
    unawaited(_sseSubscription?.cancel());
    _sseSubscription = null;
    _profile = null;
    _session = null;
    _queue = const <QueuedPrompt>[];
    _conversationState = const ConversationState();
    _dispatchInProgress = false;
    _pendingSendNowPromptId = null;
  }

  /// Explicitly cancels the active session's current generation, then
  /// dispatches [promptId] once the session settles idle. [promptId] must
  /// currently be `queued` in the active session.
  ///
  /// This never retries: if the abort call itself fails, `sendNow` returns
  /// a failure immediately and the normal queue-head dispatch resumes.
  Future<Result<void, QueueSendNowFailure>> sendNow(String promptId) async {
    final profile = _profile;
    final session = _session;
    if (profile == null || session == null) {
      return const Err(QueueSendNowFailure.noActiveSession);
    }

    final prompt = _findPrompt(promptId);
    if (prompt == null) {
      return const Err(QueueSendNowFailure.promptNotFound);
    }
    if (prompt.state != QueuedPromptState.queued) {
      return const Err(QueueSendNowFailure.promptNotQueued);
    }

    final token = _activationToken;
    // Set before aborting so a session-status update that races the abort
    // call is gated on this pending send-now instead of dispatching the
    // normal queue head.
    _pendingSendNowPromptId = promptId;

    final abortResult = await _chatRepository.abortSession(profile, session);
    if (_isStale(token)) {
      return const Err(QueueSendNowFailure.noActiveSession);
    }
    if (abortResult is Err<bool, ChatFailure>) {
      _pendingSendNowPromptId = null;
      return const Err(QueueSendNowFailure.abortFailed);
    }
    if (abortResult case Ok<bool, ChatFailure>(value: final didAbort)) {
      if (!didAbort) {
        _pendingSendNowPromptId = null;
        return const Err(QueueSendNowFailure.abortFailed);
      }
    }

    final statusResult = await _chatRepository.sessionStatus(profile, session);
    if (_isStale(token)) {
      return const Err(QueueSendNowFailure.noActiveSession);
    }
    if (statusResult case Ok<SessionExecutionState, ChatFailure>(
      value: final state,
    )) {
      _applySessionState(session.id, state);
    } else {
      _pendingSendNowPromptId = null;
      return const Err(QueueSendNowFailure.statusUnavailable);
    }

    _maybeDispatch();
    return const Ok(null);
  }

  /// Permanently disposes this coordinator. Cancels any subscription and
  /// releases every reference; [activate] must not be called afterwards.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    await deactivate();
    _disposed = true;
  }

  void _applySessionState(String sessionId, SessionExecutionState state) {
    _conversationState = reduceConversationEvent(
      _conversationState,
      SessionStatusEvent(sessionId: sessionId, state: state),
    );
  }

  void _maybeDispatch() {
    if (_disposed || _dispatchInProgress) {
      return;
    }
    if (_profile == null || _session == null) {
      return;
    }

    final pendingSendNowId = _pendingSendNowPromptId;
    if (pendingSendNowId != null) {
      if (currentSessionState is! SessionIdle) {
        return;
      }
      _pendingSendNowPromptId = null;
      final prompt = _findPrompt(pendingSendNowId);
      if (prompt == null || prompt.state != QueuedPromptState.queued) {
        return;
      }
      unawaited(_dispatch(prompt));
      return;
    }

    if (currentSessionState is! SessionIdle) {
      return;
    }
    if (_hasSendingPrompt() || _hasPendingSubmissionUnknown()) {
      return;
    }
    final head = _headQueuedPrompt();
    if (head == null) {
      return;
    }
    unawaited(_dispatch(head));
  }

  Future<void> _dispatch(QueuedPrompt prompt) async {
    _dispatchInProgress = true;
    final token = _activationToken;
    final profile = _profile!;
    final session = _session!;

    final sendingResult = await _queueRepository.markSending(prompt.id);
    if (_isStale(token)) {
      return;
    }
    if (sendingResult is Err<QueuedPrompt, QueueFailure>) {
      // Another writer already moved this prompt out of `queued` (for
      // example it was removed); drop this attempt and let the next queue
      // update decide what to dispatch.
      _dispatchInProgress = false;
      return;
    }

    final sendResult = await _chatRepository.sendPrompt(
      profile,
      session,
      prompt.promptText,
    );
    if (_isStale(token)) {
      return;
    }

    if (sendResult is Ok<void, ChatFailure>) {
      // A `204` from `prompt_async` is the server's definitive acceptance.
      await _queueRepository.markAcknowledged(prompt.id);
      // Do not dispatch the next queue entry until the server reports an
      // explicit terminal state. The busy event may arrive after this 204.
      _applySessionState(session.id, const SessionBusy());
    } else {
      // Any other outcome leaves acceptance genuinely unknown; Prompt
      // never retries automatically.
      await _queueRepository.markSubmissionUnknown(prompt.id);
    }
    if (_isStale(token)) {
      return;
    }

    _dispatchInProgress = false;
    _maybeDispatch();
  }

  QueuedPrompt? _headQueuedPrompt() {
    for (final prompt in _queue) {
      if (prompt.state == QueuedPromptState.queued) {
        return prompt;
      }
    }
    return null;
  }

  QueuedPrompt? _findPrompt(String id) {
    for (final prompt in _queue) {
      if (prompt.id == id) {
        return prompt;
      }
    }
    return null;
  }

  bool _hasSendingPrompt() {
    return _queue.any((prompt) => prompt.state == QueuedPromptState.sending);
  }

  bool _hasPendingSubmissionUnknown() {
    return _queue.any(
      (prompt) =>
          prompt.state == QueuedPromptState.paused &&
          prompt.pauseReason == QueuePauseReason.submissionUnknown,
    );
  }

  bool _isStale(int token) => _disposed || token != _activationToken;

  void _requireNotDisposed() {
    if (_disposed) {
      throw StateError('QueueSendCoordinator was already disposed.');
    }
  }
}
