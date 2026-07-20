import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_load_result.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session-1',
    projectId: 'project-1',
    directory: '/workspace/project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  test('maps text parts from user and assistant messages', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/session/session-1/message');
      expect(request.url.queryParameters['directory'], '/workspace/project');
      expect(request.url.queryParameters['limit'], '100');
      return http.Response(
        '[{"info":{"id":"user-1","role":"user",'
        '"time":{"created":1000}},"parts":['
        '{"type":"text","text":"Explain this"}]},'
        '{"info":{"id":"assistant-1","role":"assistant",'
        '"time":{"created":2000}},"parts":['
        '{"type":"reasoning","text":"Internal"},'
        '{"type":"text","text":"Here is an explanation."}]}]',
        200,
      );
    });
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, session);

    expect(result, isA<ChatLoaded>());
    final messages = (result as ChatLoaded).messages;
    expect(messages, hasLength(2));
    expect(messages.first.role, ChatMessageRole.user);
    expect(messages.first.text, 'Explain this');
    expect(messages.last.role, ChatMessageRole.assistant);
    expect(messages.last.text, 'Here is an explanation.');
  });

  test('maps rejected requests to an authorization failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = ChatRepository(
      OpenCodeChatService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile, session);

    expect(result, isA<ChatLoadFailed>());
    expect((result as ChatLoadFailed).failure, ChatFailure.unauthorized);
  });
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore(this._password);

  final String? _password;

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => _password;

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
