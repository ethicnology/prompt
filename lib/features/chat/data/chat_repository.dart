import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../../data/remote/opencode_event_service.dart';
import '../../connection/connection.dart';
import '../../sessions/sessions.dart';
import '../../queue/queue.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import '../domain/session_execution_state.dart';
import '../domain/session_block_reason.dart';
import '../domain/session_artifacts.dart';
import '../domain/conversation_event.dart';
import '../domain/conversation_state.dart';
import 'opencode_chat_service.dart';
import 'chat_data_mapper.dart';
import 'conversation_sync.dart';

class ChatRepository {
  ChatRepository(this._chatService, this._credentialsStore);

  final OpenCodeChatService _chatService;
  final CredentialsStore _credentialsStore;

  final ValueNotifier<ConversationRepositoryState> _conversation =
      ValueNotifier(
        const ConversationRepositoryState(
          messages: <ChatMessage>[],
          conversation: ConversationState(),
        ),
      );
  final ValueNotifier<ConversationState> _conversationState = ValueNotifier(
    const ConversationState(),
  );
  final List<_RecordedEvent> _events = <_RecordedEvent>[];
  int _eventSequence = 0;
  int _loadGeneration = 0;
  OpenCodeSession? _activeSession;

  ValueListenable<ConversationRepositoryState> get conversationUpdates =>
      _conversation;

  ValueListenable<ConversationState> get conversationStateUpdates =>
      _conversationState;

  void activateConversation(OpenCodeSession session) {
    if (_activeSession?.id == session.id &&
        _activeSession?.directory == session.directory) {
      return;
    }
    _activeSession = session;
    _events.clear();
    _conversation.value = const ConversationRepositoryState(
      messages: <ChatMessage>[],
      conversation: ConversationState(),
    );
    _conversationState.value = const ConversationState();
  }

  void deactivateConversation() {
    _activeSession = null;
    _events.clear();
    _conversation.value = const ConversationRepositoryState(
      messages: <ChatMessage>[],
      conversation: ConversationState(),
    );
    _conversationState.value = const ConversationState();
  }

  void applyEvent(ConversationEvent event) {
    if (_activeSession == null || event.sessionId != _activeSession!.id) return;
    final state = reduceConversationEvent(
      _conversation.value.conversation,
      event,
    );
    _eventSequence++;
    _events.add(_RecordedEvent(_eventSequence, event));
    final messages = _applyRemoval(event, _conversation.value.messages);
    _publish(state, messages);
  }

  void applyEnvelope(OpenCodeEventEnvelope envelope, OpenCodeSession session) {
    if (_activeSession?.id != session.id) return;
    final event = mapConversationEvent(
      envelope,
      sessionId: session.id,
      directory: session.directory,
    );
    if (event != null) applyEvent(event);
  }

  void applySessionState(String sessionId, SessionExecutionState state) {
    applyEvent(SessionStatusEvent(sessionId: sessionId, state: state));
  }

  void applyBlocked(String sessionId, PendingApproval approval) {
    applyEvent(
      SessionBlockedEvent(
        sessionId: sessionId,
        reason: approval is PendingQuestionApproval
            ? SessionBlockReason.question
            : SessionBlockReason.permission,
        detail: approval,
      ),
    );
  }

  void clearApproval(String sessionId) {
    final state = clearPendingApproval(
      _conversation.value.conversation,
      sessionId,
    );
    _publish(state, _conversation.value.messages);
  }

  Future<ChatLoadResult> load(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    final loadGeneration = ++_loadGeneration;
    try {
      final snapshotStart = _eventSequence;
      final password = await _credentialsStore.readPassword(profile.id);
      final records = await _chatService.listMessages(
        profile,
        password,
        session,
      );
      if (loadGeneration != _loadGeneration) {
        return ChatLoaded(_conversation.value.messages);
      }
      final messages = records
          .where(
            (record) => record.role == 'user' || record.role == 'assistant',
          )
          .map(mapChatMessage)
          .toList(growable: false);
      final replay = _events.where((event) => event.sequence > snapshotStart);
      final stateAtSnapshotStart = _conversation.value.conversation;
      var state = ConversationState(
        sessionStates: stateAtSnapshotStart.sessionStates,
        sessionBlocks: stateAtSnapshotStart.sessionBlocks,
        pendingApprovals: stateAtSnapshotStart.pendingApprovals,
      );
      var consolidatedMessages = messages;
      for (final event in replay) {
        state = reduceConversationEvent(state, event.event);
        consolidatedMessages = _applyRemoval(event.event, consolidatedMessages);
      }
      _events.removeWhere((event) => event.sequence <= snapshotStart);
      _publish(state, consolidatedMessages);
      return ChatLoaded(_conversation.value.messages);
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const ChatLoadFailed(ChatFailure.unauthorized);
      }
      return const ChatLoadFailed(ChatFailure.unexpectedResponse);
    } on TimeoutException {
      return const ChatLoadFailed(ChatFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const ChatLoadFailed(ChatFailure.unexpectedResponse);
    } on http.ClientException {
      return const ChatLoadFailed(ChatFailure.unavailable);
    } on FormatException {
      return const ChatLoadFailed(ChatFailure.unexpectedResponse);
    }
  }

  void _publish(ConversationState state, List<ChatMessage> restMessages) {
    final messages = mergeConversationMessages(restMessages, state.messages);
    _conversation.value = ConversationRepositoryState(
      messages: List.unmodifiable(messages),
      conversation: state,
    );
    _conversationState.value = state;
  }

  List<ChatMessage> _applyRemoval(
    ConversationEvent event,
    List<ChatMessage> messages,
  ) {
    if (event case MessageRemovedEvent(:final messageId)) {
      return messages.where((message) => message.id != messageId).toList();
    }
    if (event case MessagePartRemovedEvent(:final messageId, :final partId)) {
      return [
        for (final message in messages)
          if (message.id == messageId)
            ChatMessage(
              id: message.id,
              role: message.role,
              createdAt: message.createdAt,
              text: message.text,
              error: message.error,
              details: message.details
                  .where((detail) => detail.id != partId)
                  .toList(growable: false),
            )
          else
            message,
      ];
    }
    return messages;
  }

  Future<Result<SessionArtifactsReady, SessionArtifactsFailure>> loadArtifacts(
    ServerProfile profile,
    OpenCodeSession session, {
    String? messageId,
  }) {
    return _runArtifacts(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      final results = await Future.wait([
        _chatService.listTodos(profile, password, session),
        _chatService.listDiffs(
          profile,
          password,
          session,
          messageId: messageId,
        ),
      ]);
      return SessionArtifactsReady(
        todos: results[0]
            .cast<OpenCodeTodoRecord>()
            .map(mapSessionTodo)
            .toList(growable: false),
        diffs: results[1]
            .cast<OpenCodeFileDiffRecord>()
            .map(mapSessionDiff)
            .toList(growable: false),
      );
    });
  }

  /// Sends [text] to [session] without waiting for the assistant's reply.
  /// Never logs [text]; a caller must not log the returned failure's raw
  /// server detail either, since none is carried on [ChatFailure].
  Future<Result<void, ChatFailure>> sendPrompt(
    ServerProfile profile,
    OpenCodeSession session,
    String text, {
    List<QueuedAttachment> attachments = const <QueuedAttachment>[],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.sendPromptAsync(
        profile,
        password,
        session,
        text,
        attachments: attachments,
        executionOptions: executionOptions,
      );
    });
  }

  Future<Result<void, ChatFailure>> executeCommand(
    ServerProfile profile,
    OpenCodeSession session,
    String command,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.executeCommand(
        profile,
        password,
        session,
        command,
        arguments,
        executionOptions: executionOptions,
      );
    });
  }

  /// Explicitly cancels [session]'s active generation. The success value
  /// reports whether the server actually aborted something.
  Future<Result<bool, ChatFailure>> abortSession(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      return _chatService.abortSession(profile, password, session);
    });
  }

  /// Responds to a pending tool-call permission with [response]. Never
  /// logs [permissionId] or any permission detail; a caller must not log
  /// the returned failure's raw server detail either, since none is
  /// carried on [ChatFailure].
  Future<Result<void, ChatFailure>> respondToPermission(
    ServerProfile profile,
    OpenCodeSession session,
    String permissionId,
    PermissionResponse response,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.respondToPermission(
        profile,
        password,
        session,
        permissionId,
        response,
      );
    });
  }

  /// Answers a pending question request with [answers]. Never logs
  /// [requestId] or any answer text.
  Future<Result<void, ChatFailure>> replyToQuestion(
    ServerProfile profile,
    OpenCodeSession session,
    String requestId,
    List<List<String>> answers,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.replyToQuestion(
        profile,
        password,
        session,
        requestId,
        answers,
      );
    });
  }

  /// Rejects a pending question request outright. Never logs [requestId].
  Future<Result<void, ChatFailure>> rejectQuestion(
    ServerProfile profile,
    OpenCodeSession session,
    String requestId,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.rejectQuestion(profile, password, session, requestId);
    });
  }

  /// The execution state of [session], as reported by the authoritative
  /// `GET /session/status` endpoint rather than an SSE event. A session the
  /// server omits from its response has no active or retrying work.
  Future<Result<SessionExecutionState, ChatFailure>> sessionStatus(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      final statuses = await _chatService.fetchSessionStatuses(
        profile,
        password,
        session.directory,
      );
      return statuses[session.id] ?? const SessionIdle();
    });
  }

  Future<Result<List<PendingApproval>, ChatFailure>> pendingApprovals(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      return _chatService.listPendingApprovals(profile, password, session);
    });
  }

  Future<Result<T, ChatFailure>> _run<T>(Future<T> Function() operation) async {
    try {
      return Ok(await operation());
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const Err(ChatFailure.unauthorized);
      }
      return const Err(ChatFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(ChatFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(ChatFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(ChatFailure.unavailable);
    } on FormatException {
      return const Err(ChatFailure.unexpectedResponse);
    }
  }

  Future<Result<T, SessionArtifactsFailure>> _runArtifacts<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return Ok(await operation());
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const Err(SessionArtifactsFailure.unauthorized);
      }
      return const Err(SessionArtifactsFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(SessionArtifactsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(SessionArtifactsFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(SessionArtifactsFailure.unavailable);
    } on FormatException {
      return const Err(SessionArtifactsFailure.unexpectedResponse);
    }
  }
}

class _RecordedEvent {
  const _RecordedEvent(this.sequence, this.event);

  final int sequence;
  final ConversationEvent event;
}
