import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/credentials_store.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/terminal/data/opencode_terminal_service.dart';
import 'package:prompt/features/terminal/data/terminal_repository.dart';
import 'package:prompt/features/terminal/domain/remote_terminal.dart';

void main() {
  final profile = ServerProfile(origin: Uri.parse('http://10.80.0.1:4096'));
  test('lists and creates terminals for the selected server directory', () async {
    final requests = <http.Request>[];
    final repository = OpenCodeTerminalRepository(
      OpenCodeTerminalService(
        OpenCodeTransport(
          MockClient((request) async {
            requests.add(request);
            const terminal =
                '{"id":"pty-1","title":"shell","command":"sh","args":[],"cwd":"/work","status":"running","pid":1}';
            return http.Response(
              request.method == 'GET' ? '[$terminal]' : terminal,
              200,
            );
          }),
        ),
      ),
      const _Credentials(),
    );
    final listed = await repository.list(profile, '/work');
    final created = await repository.create(profile, '/work');
    expect(listed, isA<Ok<List<RemoteTerminal>, RemoteTerminalFailure>>());
    expect(created, isA<Ok<RemoteTerminal, RemoteTerminalFailure>>());
    expect(requests.map((request) => request.method), ['GET', 'POST']);
    expect(requests.every((request) => request.url.path == '/pty'), isTrue);
    expect(
      requests.every(
        (request) => request.url.queryParameters['directory'] == '/work',
      ),
      isTrue,
    );
  });

  test('maps a missing experimental endpoint to unavailable', () async {
    final repository = OpenCodeTerminalRepository(
      OpenCodeTerminalService(
        OpenCodeTransport(MockClient((_) async => http.Response('', 404))),
      ),
      const _Credentials(),
    );
    final result = await repository.list(profile, '/work');
    expect(
      result,
      isA<Err<List<RemoteTerminal>, RemoteTerminalFailure>>().having(
        (failure) => failure.failure,
        'failure',
        RemoteTerminalFailure.unavailable,
      ),
    );
  });
}

class _Credentials implements CredentialsStore {
  const _Credentials();
  @override
  Future<void> clearPassword(String profileId) async {}
  @override
  Future<String?> readPassword(String profileId) async => null;
  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
