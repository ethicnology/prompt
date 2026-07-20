import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';
import 'package:prompt/features/sessions/data/sessions_repository.dart';
import 'package:prompt/features/sessions/domain/session_load_result.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  test('loads and orders sessions from every OpenCode project', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/project') {
        return http.Response(
          '[{"id":"project-a","worktree":"/workspace/alpha"},'
          '{"id":"project-b","worktree":"/workspace/beta"}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/alpha') {
        return http.Response(
          '[{"id":"older","projectID":"project-a",'
          '"directory":"/workspace/alpha","title":"Older session",'
          '"time":{"created":1000,"updated":2000}}]',
          200,
        );
      }
      if (request.url.path == '/session' &&
          request.url.queryParameters['directory'] == '/workspace/beta') {
        return http.Response(
          '[{"id":"newer","projectID":"project-b",'
          '"directory":"/workspace/beta","title":"Newer session",'
          '"time":{"created":1000,"updated":3000},'
          '"summary":{"files":2,"additions":3,"deletions":1}}]',
          200,
        );
      }
      return http.Response('', 404);
    });
    final repository = SessionsRepository(
      OpenCodeSessionsService(client),
      const _PasswordStore('secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoaded>());
    final sessions = (result as SessionsLoaded).sessions;
    expect(sessions.map((session) => session.id), ['newer', 'older']);
    expect(sessions.first.changedFiles, 2);
  });

  test('maps a rejected session request to an authorization failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = SessionsRepository(
      OpenCodeSessionsService(client),
      const _PasswordStore('wrong-secret'),
    );

    final result = await repository.load(profile);

    expect(result, isA<SessionsLoadFailed>());
    expect(
      (result as SessionsLoadFailed).failure,
      SessionsFailure.unauthorized,
    );
  });
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore(this._password);

  final String? _password;

  @override
  Future<void> clearPassword() async {}

  @override
  Future<String?> readPassword() async => _password;

  @override
  Future<void> savePassword(String? password) async {}
}
