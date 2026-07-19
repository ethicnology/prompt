import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prompt/features/connection/data/connection_repository.dart';
import 'package:prompt/features/connection/data/opencode_health_service.dart';
import 'package:prompt/features/connection/domain/connection_result.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';

void main() {
  final profile = ServerProfile(
    origin: Uri(scheme: 'http', host: '10.80.0.1', port: 4096),
    username: 'prompt',
  );

  test(
    'tests the configured OpenCode health endpoint with basic auth',
    () async {
      late http.Request request;
      final client = MockClient((incomingRequest) async {
        request = incomingRequest;
        return http.Response('', 200);
      });
      final repository = ConnectionRepository(OpenCodeHealthService(client));

      final result = await repository.test(profile, 'secret');

      expect(result, isA<ConnectionSucceeded>());
      expect(request.url, Uri.parse('http://10.80.0.1:4096/global/health'));
      expect(
        request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('prompt:secret'))}',
      );
    },
  );

  test('maps rejected credentials to a recoverable failure', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final repository = ConnectionRepository(OpenCodeHealthService(client));

    final result = await repository.test(profile, 'wrong-secret');

    expect(result, isA<ConnectionFailed>());
    expect(
      (result as ConnectionFailed).failure,
      ConnectionFailure.unauthorized,
    );
  });

  test(
    'rejects unsupported connection schemes before making a request',
    () async {
      final client = MockClient((_) async => http.Response('', 200));
      final repository = ConnectionRepository(OpenCodeHealthService(client));
      final unsupportedProfile = ServerProfile(
        origin: Uri(scheme: 'ftp', host: '10.80.0.1', port: 4096),
      );

      final result = await repository.test(unsupportedProfile, null);

      expect(result, isA<ConnectionFailed>());
      expect(
        (result as ConnectionFailed).failure,
        ConnectionFailure.invalidAddress,
      );
    },
  );

  test('rejects public HTTP origins before making a request', () async {
    final client = MockClient((_) async => http.Response('', 200));
    final repository = ConnectionRepository(OpenCodeHealthService(client));
    final publicProfile = ServerProfile(
      origin: Uri.parse('http://198.51.100.1:4096'),
    );

    final result = await repository.test(publicProfile, null);

    expect(result, isA<ConnectionFailed>());
    expect(
      (result as ConnectionFailed).failure,
      ConnectionFailure.invalidAddress,
    );
  });
}
