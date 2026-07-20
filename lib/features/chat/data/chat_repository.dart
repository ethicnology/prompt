import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/permission_response.dart';
import '../domain/session_execution_state.dart';
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

  /// Sends [text] to [session] without waiting for the assistant's reply.
  /// Never logs [text]; a caller must not log the returned failure's raw
  /// server detail either, since none is carried on [ChatFailure].
  Future<Result<void, ChatFailure>> sendPrompt(
    ServerProfile profile,
    OpenCodeSession session,
    String text,
  ) {
    return _run(() async {
      final password = await _credentialsStore.readPassword(profile.id);
      await _chatService.sendPromptAsync(profile, password, session, text);
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
}
