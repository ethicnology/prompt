import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/chat_repository.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/chat_load_result.dart';
import 'package:prompt/features/chat/domain/chat_message.dart';
import 'package:prompt/features/chat/domain/permission_response.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';
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

  group('sendPrompt', () {
    test('accepts a prompt on an empty 204 response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session-1/prompt_async');
        expect(request.url.queryParameters['directory'], session.directory);
        return http.Response('', 204);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sendPrompt(
        profile,
        session,
        'Explain this',
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected send to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sendPrompt(
        profile,
        session,
        'Explain this',
      );

      expect(result, isA<Err<void, ChatFailure>>());
      expect(
        (result as Err<void, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });

    test(
      'maps a malformed 204 body to an unexpected-response failure',
      () async {
        final client = MockClient((_) async => http.Response('{}', 204));
        final repository = ChatRepository(
          OpenCodeChatService(OpenCodeTransport(client)),
          const _PasswordStore('secret'),
        );

        final result = await repository.sendPrompt(
          profile,
          session,
          'Explain this',
        );

        expect(result, isA<Err<void, ChatFailure>>());
        expect(
          (result as Err<void, ChatFailure>).failure,
          ChatFailure.unexpectedResponse,
        );
      },
    );
  });

  group('abortSession', () {
    test('returns the server-reported abort outcome', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session-1/abort');
        expect(request.url.queryParameters['directory'], session.directory);
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.abortSession(profile, session);

      expect(result, isA<Ok<bool, ChatFailure>>());
      expect((result as Ok<bool, ChatFailure>).value, isTrue);
    });

    test('maps a rejected abort to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.abortSession(profile, session);

      expect(result, isA<Err<bool, ChatFailure>>());
      expect(
        (result as Err<bool, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });
  });

  group('respondToPermission', () {
    test('succeeds when the server processes the response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session-1/permissions/perm-1');
        expect(jsonDecode(request.body), {'response': 'once'});
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.respondToPermission(
        profile,
        session,
        'perm-1',
        PermissionResponse.once,
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected response to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.respondToPermission(
        profile,
        session,
        'perm-1',
        PermissionResponse.reject,
      );

      expect(result, isA<Err<void, ChatFailure>>());
      expect(
        (result as Err<void, ChatFailure>).failure,
        ChatFailure.unauthorized,
      );
    });
  });

  group('replyToQuestion', () {
    test('sends every question\'s answers in order', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/question/que-1/reply');
        expect(jsonDecode(request.body), {
          'answers': [
            ['Postgres'],
          ],
        });
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.replyToQuestion(
        profile,
        session,
        'que-1',
        [
          ['Postgres'],
        ],
      );

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected reply to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.replyToQuestion(
        profile,
        session,
        'que-1',
        [
          ['Postgres'],
        ],
      );

      expect(result, isA<Err<void, ChatFailure>>());
    });
  });

  group('rejectQuestion', () {
    test('succeeds when the server rejects the question', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/question/que-1/reject');
        return http.Response('true', 200);
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.rejectQuestion(profile, session, 'que-1');

      expect(result, isA<Ok<void, ChatFailure>>());
    });

    test('maps a rejected reject call to an authorization failure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.rejectQuestion(profile, session, 'que-1');

      expect(result, isA<Err<void, ChatFailure>>());
    });
  });

  group('sessionStatus', () {
    test('maps this session\'s entry from the status response', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/session/status');
        expect(request.url.queryParameters['directory'], session.directory);
        return http.Response(
          '{"session-1":{"type":"busy"},"session-2":{"type":"idle"}}',
          200,
        );
      });
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sessionStatus(profile, session);

      expect(result, isA<Ok<SessionExecutionState, ChatFailure>>());
      expect(
        (result as Ok<SessionExecutionState, ChatFailure>).value,
        isA<SessionBusy>(),
      );
    });

    test(
      'defaults to idle when the session is absent from the response',
      () async {
        final client = MockClient((_) async => http.Response('{}', 200));
        final repository = ChatRepository(
          OpenCodeChatService(OpenCodeTransport(client)),
          const _PasswordStore('secret'),
        );

        final result = await repository.sessionStatus(profile, session);

        expect(result, isA<Ok<SessionExecutionState, ChatFailure>>());
        expect(
          (result as Ok<SessionExecutionState, ChatFailure>).value,
          isA<SessionIdle>(),
        );
      },
    );

    test(
      'maps a rejected status request to an authorization failure',
      () async {
        final client = MockClient((_) async => http.Response('', 401));
        final repository = ChatRepository(
          OpenCodeChatService(OpenCodeTransport(client)),
          const _PasswordStore('secret'),
        );

        final result = await repository.sessionStatus(profile, session);

        expect(result, isA<Err<SessionExecutionState, ChatFailure>>());
        expect(
          (result as Err<SessionExecutionState, ChatFailure>).failure,
          ChatFailure.unauthorized,
        );
      },
    );

    test('maps a malformed status response to an unexpected-response '
        'failure', () async {
      final client = MockClient((_) async => http.Response('not-json', 200));
      final repository = ChatRepository(
        OpenCodeChatService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.sessionStatus(profile, session);

      expect(result, isA<Err<SessionExecutionState, ChatFailure>>());
      expect(
        (result as Err<SessionExecutionState, ChatFailure>).failure,
        ChatFailure.unexpectedResponse,
      );
    });
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
