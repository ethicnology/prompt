import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/security/credentials_store.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/data/opencode_sessions_service.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
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
      final password = await _credentialsStore.readPassword();
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
    } on http.ClientException {
      return const ChatLoadFailed(ChatFailure.unavailable);
    } on FormatException {
      return const ChatLoadFailed(ChatFailure.unexpectedResponse);
    }
  }
}
