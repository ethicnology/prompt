import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/chat/data/opencode_chat_service.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );
  final session = OpenCodeSession(
    id: 'session 1',
    projectId: 'project-1',
    directory: '/workspace/my project',
    title: 'A session',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );

  group('sendPromptAsync', () {
    test('sends a Basic-authorized request with an encoded path, '
        'directory query, and a text part body', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await service.sendPromptAsync(profile, 'secret', session, 'Hello');

      final request = captured!;
      expect(request.method, 'POST');
      expect(request.url.path, '/session/session%201/prompt_async');
      expect(request.url.queryParameters['directory'], session.directory);
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
      );
      expect(jsonDecode(request.body), {
        'parts': [
          {'type': 'text', 'text': 'Hello'},
        ],
      });
    });

    test('succeeds only on an empty 204 response', () async {
      final client = MockClient((_) async => http.Response('', 204));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.sendPromptAsync(profile, 'secret', session, 'Hello'),
        completes,
      );
    });

    test('rejects a 204 response with a non-empty body', () async {
      final client = MockClient((_) async => http.Response('{}', 204));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.sendPromptAsync(profile, 'secret', session, 'Hello'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a non-204 success status', () async {
      final client = MockClient((_) async => http.Response('', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.sendPromptAsync(profile, 'secret', session, 'Hello'),
        throwsA(isA<OpenCodeHttpFailure>()),
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.sendPromptAsync(profile, 'secret', session, 'Hello'),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('abortSession', () {
    test(
      'posts to the abort endpoint with authorization and directory',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response('true', 200);
        });
        final service = OpenCodeChatService(OpenCodeTransport(client));

        final aborted = await service.abortSession(profile, 'secret', session);

        expect(aborted, isTrue);
        final request = captured!;
        expect(request.method, 'POST');
        expect(request.url.path, '/session/session%201/abort');
        expect(request.url.queryParameters['directory'], session.directory);
        expect(
          request.headers['authorization'],
          'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
        );
      },
    );

    test('returns false when the server reports nothing was aborted', () async {
      final client = MockClient((_) async => http.Response('false', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final aborted = await service.abortSession(profile, 'secret', session);

      expect(aborted, isFalse);
    });

    test('rejects a non-boolean response body', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.abortSession(profile, 'secret', session),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.abortSession(profile, 'secret', session),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });

  group('fetchSessionStatuses', () {
    test('gets the status endpoint with authorization and directory', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      });
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await service.fetchSessionStatuses(
        profile,
        'secret',
        '/workspace/my project',
      );

      final request = captured!;
      expect(request.method, 'GET');
      expect(request.url.path, '/session/status');
      expect(request.url.queryParameters['directory'], '/workspace/my project');
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('opencode:secret'))}',
      );
    });

    test('maps idle, busy, and retry status entries', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'idle-session': {'type': 'idle'},
            'busy-session': {'type': 'busy'},
            'retrying-session': {
              'type': 'retry',
              'attempt': 2,
              'message': 'rate limited',
              'next': 5000,
            },
          }),
          200,
        ),
      );
      final service = OpenCodeChatService(OpenCodeTransport(client));

      final statuses = await service.fetchSessionStatuses(
        profile,
        'secret',
        '/workspace/project',
      );

      expect(statuses['idle-session'], isA<SessionIdle>());
      expect(statuses['busy-session'], isA<SessionBusy>());
      final retrying = statuses['retrying-session'] as SessionRetrying;
      expect(retrying.attempt, 2);
      expect(retrying.nextAttemptAtMillis, 5000);
    });

    test('rejects a response that is not a JSON object', () async {
      final client = MockClient((_) async => http.Response('[]', 200));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.fetchSessionStatuses(profile, 'secret', '/workspace/project'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a status entry with an unrecognized type', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'session-1': {'type': 'unknown'},
          }),
          200,
        ),
      );
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.fetchSessionStatuses(profile, 'secret', '/workspace/project'),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps an unauthorized response to an OpenCodeHttpFailure', () async {
      final client = MockClient((_) async => http.Response('', 401));
      final service = OpenCodeChatService(OpenCodeTransport(client));

      await expectLater(
        service.fetchSessionStatuses(profile, 'secret', '/workspace/project'),
        throwsA(
          isA<OpenCodeHttpFailure>().having(
            (failure) => failure.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
    });
  });
}
