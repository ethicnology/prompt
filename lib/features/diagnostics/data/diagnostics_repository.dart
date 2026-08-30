import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/diagnostics_load_result.dart';
import 'opencode_diagnostics_service.dart';

class DiagnosticsRepository {
  DiagnosticsRepository(this._service, this._credentialsStore);

  final OpenCodeDiagnosticsService _service;
  final CredentialsStore _credentialsStore;

  Future<DiagnosticsLoadResult> load(ServerProfile profile) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      return DiagnosticsLoaded(await _service.fetch(profile, password));
    } on OpenCodeHttpFailure catch (failure) {
      return DiagnosticsLoadFailed(
        failure.statusCode == 401 || failure.statusCode == 403
            ? DiagnosticsFailure.unauthorized
            : DiagnosticsFailure.unexpectedResponse,
      );
    } on TimeoutException {
      return const DiagnosticsLoadFailed(DiagnosticsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const DiagnosticsLoadFailed(DiagnosticsFailure.unexpectedResponse);
    } on http.ClientException {
      return const DiagnosticsLoadFailed(DiagnosticsFailure.unavailable);
    } on FormatException {
      return const DiagnosticsLoadFailed(DiagnosticsFailure.unexpectedResponse);
    }
  }

  Future<DiagnosticsReloadResult> reload(ServerProfile profile) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      await _service.disposeGlobalInstances(profile, password);
      return const DiagnosticsReloaded();
    } on OpenCodeHttpFailure catch (failure) {
      return DiagnosticsReloadFailed(_httpFailure(failure.statusCode));
    } on TimeoutException {
      return const DiagnosticsReloadFailed(DiagnosticsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const DiagnosticsReloadFailed(
        DiagnosticsFailure.unexpectedResponse,
      );
    } on http.ClientException {
      return const DiagnosticsReloadFailed(DiagnosticsFailure.unavailable);
    } on FormatException {
      return const DiagnosticsReloadFailed(
        DiagnosticsFailure.unexpectedResponse,
      );
    }
  }

  DiagnosticsFailure _httpFailure(int statusCode) =>
      statusCode == 401 || statusCode == 403
      ? DiagnosticsFailure.unauthorized
      : DiagnosticsFailure.unexpectedResponse;
}
