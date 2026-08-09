import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../../queue/domain/prompt_execution_options.dart';
import '../../queue/domain/queued_prompt.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import '../domain/session_execution_state.dart';
import '../domain/session_artifacts.dart';
import 'opencode_chat_service.dart';

class ChatRepository {
  ChatRepository(this._chatService, this._credentialsStore);

  final OpenCodeChatService _chatService;
  final CredentialsStore _credentialsStore;

  Future<ChatLoadResult> load(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      final records = await _chatService.listMessages(
        profile,
        password,
        session,
      );
      final messages = records
          .where(
            (record) => record.role == 'user' || record.role == 'assistant',
          )
          .map(
            (record) => ChatMessage(
              id: record.id,
              role: record.role == 'user'
                  ? ChatMessageRole.user
                  : ChatMessageRole.assistant,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                record.createdAtMillis,
              ),
              text: record.text,
              details: record.details.map(_toDetail).toList(growable: false),
              error: record.error,
            ),
          )
          .toList(growable: false);
      return ChatLoaded(messages);
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
            .map(_toTodo)
            .toList(growable: false),
        diffs: results[1]
            .cast<OpenCodeFileDiffRecord>()
            .map(_toDiff)
            .toList(growable: false),
      );
    });
  }

  SessionTodo _toTodo(OpenCodeTodoRecord record) => SessionTodo(
    id: record.id,
    content: record.content,
    // `status` and `priority` are open strings in OpenCode's schema. An
    // unknown value must not hide every todo, so it falls back instead of
    // failing the whole panel.
    status: switch (record.status) {
      'in_progress' => SessionTodoStatus.inProgress,
      'completed' => SessionTodoStatus.completed,
      'cancelled' => SessionTodoStatus.cancelled,
      _ => SessionTodoStatus.pending,
    },
    priority: switch (record.priority) {
      'high' => SessionTodoPriority.high,
      'low' => SessionTodoPriority.low,
      _ => SessionTodoPriority.medium,
    },
  );

  SessionFileDiff _toDiff(OpenCodeFileDiffRecord record) => SessionFileDiff(
    file: record.file,
    patch: record.patch,
    additions: record.additions,
    deletions: record.deletions,
    status: record.status,
  );

  ChatMessageDetail _toDetail(OpenCodeMessageDetailRecord record) {
    return switch (record) {
      OpenCodeReasoningRecord(:final id, :final text) => ChatReasoningDetail(
        id: id,
        text: text,
      ),
      OpenCodeToolRecord(
        :final id,
        :final tool,
        :final status,
        :final input,
        :final output,
        :final error,
      ) =>
        ChatToolDetail(
          id: id,
          tool: tool,
          status: status,
          input: input,
          output: output,
          error: error,
        ),
    };
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
