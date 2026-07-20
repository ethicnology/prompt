import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/security/credentials_store.dart';
import '../domain/connection_result.dart';
import '../domain/connection_origin_policy.dart';
import '../domain/server_profile.dart';
import 'opencode_health_service.dart';

class ConnectionRepository {
  ConnectionRepository(this._healthService, this._credentialsStore);

  final OpenCodeHealthService _healthService;
  final CredentialsStore _credentialsStore;

  Future<ConnectionResult> test(ServerProfile profile, String? password) async {
    if (!ConnectionOriginPolicy.supports(profile.origin)) {
      return const ConnectionFailed(ConnectionFailure.invalidAddress);
    }

    try {
      final statusCode = await _healthService.checkHealth(profile, password);
      if (statusCode >= 200 && statusCode < 300) {
        await _credentialsStore.savePassword(password);
        return const ConnectionSucceeded();
      }
      if (statusCode == 401 || statusCode == 403) {
        return const ConnectionFailed(ConnectionFailure.unauthorized);
      }
      return const ConnectionFailed(ConnectionFailure.unexpectedResponse);
    } on TimeoutException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on http.ClientException {
      return const ConnectionFailed(ConnectionFailure.unavailable);
    } on Exception {
      return const ConnectionFailed(ConnectionFailure.secureStorageUnavailable);
    }
  }
}
