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
import 'package:prompt/features/sessions/presentation/sessions_view_model.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  test(
    'returns a typed suggestion failure for an unavailable capability',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/file') {
          return http.Response('', 404);
        }
        return http.Response('[]', 200);
      });
      final viewModel = SessionsViewModel(
        SessionsRepository(
          OpenCodeSessionsService(OpenCodeTransport(client)),
          const _PasswordStore(),
        ),
      );

      final result = await viewModel.suggestDirectories(profile, '/srv/app');

      expect(result, isA<Err<List<String>, SessionsFailure>>());
      expect(
        (result as Err<List<String>, SessionsFailure>).failure,
        SessionsFailure.unexpectedResponse,
      );
      viewModel.dispose();
    },
  );
}

class _PasswordStore implements CredentialsStore {
  const _PasswordStore();

  @override
  Future<void> clearPassword(String profileId) async {}

  @override
  Future<String?> readPassword(String profileId) async => 'secret';

  @override
  Future<void> savePassword(String profileId, String? password) async {}
}
