import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/workspace_entry.dart';
import '../domain/workspace_failure.dart';
import 'opencode_workspace_service.dart';

abstract interface class WorkspaceRepository {
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  );

  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  );

  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  );
}

class OpenCodeWorkspaceRepository implements WorkspaceRepository {
  OpenCodeWorkspaceRepository(this._service, this._credentialsStore);

  final OpenCodeWorkspaceService _service;
  final CredentialsStore _credentialsStore;

  @override
  Future<Result<WorkspaceSnapshot, WorkspaceFailure>> load(
    ServerProfile profile,
    String directory,
    String path,
  ) => _run(() async {
    final password = await _credentialsStore.readPassword(profile.id);
    final values = await Future.wait([
      _service.listFiles(profile, password, directory: directory, path: path),
      _service.status(profile, password, directory),
      _service.vcs(profile, password, directory),
    ]);
    return WorkspaceSnapshot(
      entries: List.unmodifiable(values[0] as List<WorkspaceEntry>),
      status: List.unmodifiable(values[1] as List<WorkspaceStatusEntry>),
      vcs: values[2] as WorkspaceVcsSummary,
    );
  });

  @override
  Future<Result<WorkspaceFileContent, WorkspaceFailure>> readFile(
    ServerProfile profile,
    String directory,
    String path,
  ) => _run(
    () async => _service.readFile(
      profile,
      await _credentialsStore.readPassword(profile.id),
      directory: directory,
      path: path,
    ),
  );

  @override
  Future<Result<List<WorkspaceSearchResult>, WorkspaceFailure>> search(
    ServerProfile profile,
    String directory,
    WorkspaceSearchKind kind,
    String query,
  ) => _run(
    () async => _service.search(
      profile,
      await _credentialsStore.readPassword(profile.id),
      directory: directory,
      kind: kind,
      query: query,
    ),
  );

  Future<Result<T, WorkspaceFailure>> _run<T>(
    Future<T> Function() action,
  ) async {
    try {
      return Ok(await action());
    } on OpenCodeHttpFailure catch (failure) {
      return Err(
        failure.statusCode == 401 || failure.statusCode == 403
            ? WorkspaceFailure.unauthorized
            : WorkspaceFailure.unexpectedResponse,
      );
    } on TimeoutException {
      return const Err(WorkspaceFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const Err(WorkspaceFailure.unexpectedResponse);
    } on http.ClientException {
      return const Err(WorkspaceFailure.unavailable);
    } on FormatException {
      return const Err(WorkspaceFailure.unexpectedResponse);
    }
  }
}
