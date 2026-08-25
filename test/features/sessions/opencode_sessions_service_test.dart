import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/data/remote/opencode_transport.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:prompt/features/sessions/data/opencode_sessions_service.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri.parse('http://10.80.0.1:4096'),
    username: 'opencode',
  );

  test('returns only matching directories from the server response', () async {
    final service = OpenCodeSessionsService(
      OpenCodeTransport(
        MockClient(
          (_) async => http.Response(
            '[{"type":"directory","absolute":"/srv/app"},'
            '{"type":"file","absolute":"/srv/app.txt"}]',
            200,
          ),
        ),
      ),
    );

    expect(await service.suggestDirectories(profile, null, '/srv/ap'), [
      '/srv/app',
    ]);
  });

  test('rejects malformed server directory entries', () async {
    final service = OpenCodeSessionsService(
      OpenCodeTransport(
        MockClient(
          (_) async =>
              http.Response('[{"type":"directory","absolute":42}]', 200),
        ),
      ),
    );

    expect(
      () => service.suggestDirectories(profile, null, '/srv/ap'),
      throwsA(isA<FormatException>()),
    );
  });
}
