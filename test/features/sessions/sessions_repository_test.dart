import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';
import 'package:prompt/features/sessions/domain/open_code_session.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  test('uses successful project catalogs as authoritative snapshots', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project-a","worktree":"/workspace/alpha"},'
          '{"id":"project-b","worktree":"/workspace/beta"}]',
          200,
        );
      }
      if (request.url.path == '/session' && request.url.query.isEmpty) {
        return http.Response(
          '[{"id":"older","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Older session",'
          '"time":{"created":1000,"updated":2000}},'
          '{"id":"newer","projectID":"project-b",'
          '"directory":"/workspace/beta","title":"Newer session",'
          '"time":{"created":1000,"updated":3000},'
          '"summary":{"files":2,"additions":3,"deletions":1}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/alpha') {
        return http.Response(
          '[{"id":"older","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Older session",'
          '"time":{"created":1000,"updated":2000}},'
          '{"id":"alpha-only","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Alpha only",'
          '"time":{"created":1000,"updated":4000}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/beta') {
        return http.Response('[]', 200);
      }
      return http.Response('', 404);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoaded>());
    final sessions = (result as SessionsLoaded).sessions;
    expect(sessions.map((session) => session.id), ['alpha-only', 'older']);
  });

  test('keeps the sessions that loaded when one project fails', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project-a","worktree":"/workspace/alpha"},'
          '{"id":"project-b","worktree":"/workspace/beta"}]',
          200,
        );
      }
      if (request.url.path == '/session' && request.url.query.isEmpty) {
        return http.Response(
          '[{"id":"global","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Global session",'
          '"time":{"created":1000,"updated":2000}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/alpha') {
        return http.Response(
          '[{"id":"alpha-only","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Alpha only",'
          '"time":{"created":1000,"updated":4000}}]',
          200,
        );
      }
      // The second project is unreachable for this load.
      return http.Response('', 500);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoaded>());
    expect((result as SessionsLoaded).sessions.map((session) => session.id), [
      'alpha-only',
    ]);
  });

  test(
    'falls back to the global index only for an unavailable project',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/project') {
          return http.Response(
            '[{"id":"project-a","worktree":"/workspace/alpha"},'
            '{"id":"project-b","worktree":"/workspace/beta"}]',
            200,
          );
        }
        if (request.url.path == '/session' && request.url.query.isEmpty) {
          return http.Response(
            '[{"id":"beta","projectID":"project-b",'
            '"directory":"/workspace/beta","title":"Beta session",'
            '"time":{"created":1000,"updated":2000}}]',
            200,
          );
        }
        if (request.url.queryParameters['directory'] == '/workspace/alpha') {
          return http.Response('[]', 200);
        }
        return http.Response('', 500);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.load(profile);

      expect((result as SessionsLoaded).sessions.map((session) => session.id), [
        'beta',
      ]);
    },
  );

  test(
    'keeps the global index when the project endpoint is unavailable',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/session') {
          return http.Response(
            '[{"id":"global","projectID":"project-a",'
            '"directory":"/workspace/alpha","title":"Global session",'
            '"time":{"created":1000,"updated":2000}}]',
            200,
          );
        }
        return http.Response('', 500);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.load(profile);

      expect(result, isA<SessionsLoaded>());
      final loaded = result as SessionsLoaded;
      expect(loaded.sessions.single.id, 'global');
      expect(loaded.projects, isEmpty);
    },
  );

  test('maps a rejected session request to an authorization failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = SessionsRepository(
      OpenCodeSessionsService(OpenCodeTransport(client)),
      const _PasswordStore('wrong-secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoadFailed>());
    expect(
      (result as SessionsLoadFailed).failure,
      SessionsFailure.unauthorized,
    );
  });

  test(
    'forks a session through the official endpoint and maps the result',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(_sessionJson('forked'), 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.fork(profile, _session());

      expect(result, isA<Ok<OpenCodeSession, SessionsFailure>>());
      expect(
        (result as Ok<OpenCodeSession, SessionsFailure>).value.id,
        'forked',
      );
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/session/session-1/fork');
      expect(captured!.url.queryParameters['directory'], '/workspace/project');
    },
  );

  test(
    'shares only a safe returned HTTPS URL and unshares through OpenCode',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return request.method == 'POST'
            ? http.Response(
                _sessionJson(
                  'session-1',
                  shareUrl: 'https://share.example/s/1',
                ),
                200,
              )
            : http.Response('true', 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final shared = await repository.share(profile, _session());
      final unshared = await repository.unshare(profile, _session());

      expect(
        (shared as Ok<String?, SessionsFailure>).value,
        'https://share.example/s/1',
      );
      expect(unshared, isA<Ok<void, SessionsFailure>>());
      expect(requests[0].url.path, '/session/session-1/share');
      expect(requests[1].method, 'DELETE');
      expect(requests[1].url.path, '/session/session-1/share');
    },
  );

  test(
    'reverts only the supplied message ID through the official endpoint',
    () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('true', 200);
      });
      final repository = SessionsRepository(
        OpenCodeSessionsService(OpenCodeTransport(client)),
        const _PasswordStore('secret'),
      );

      final result = await repository.revert(profile, _session(), 'message-1');

      expect((result as Ok<bool, SessionsFailure>).value, isTrue);
      expect(captured!.url.path, '/session/session-1/revert');
      expect(captured!.url.queryParameters['directory'], '/workspace/project');
      expect(captured!.body, '{"messageID":"message-1"}');
    },
  );
}

OpenCodeSession _session() => OpenCodeSession(
  id: 'session-1',
  projectId: 'project-1',
  directory: '/workspace/project',
  title: 'Session',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
);

String _sessionJson(String id, {String? shareUrl}) =>
    '''
{"id":"$id","projectID":"project-1","directory":"/workspace/project",
"title":"Session","time":{"created":1000,"updated":1000}
${shareUrl == null ? '' : ',"share":{"url":"$shareUrl"}'}}
''';

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
