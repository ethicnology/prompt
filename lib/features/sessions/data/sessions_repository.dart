import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import 'opencode_sessions_service.dart';

class SessionsRepository {
  SessionsRepository(this._sessionsService, this._credentialsStore);

  final OpenCodeSessionsService _sessionsService;
  final CredentialsStore _credentialsStore;

  Future<SessionLoadResult> load(ServerProfile profile) async {
    try {
      final password = await _credentialsStore.readPassword(profile.id);
      final projects = await _sessionsService.listProjects(profile, password);
      final sessionsByProject = await Future.wait(
        projects.map(
          (project) => _sessionsService.listSessions(
            profile,
            password,
            project.worktree,
          ),
        ),
      );
      final sessions =
          sessionsByProject
              .expand((projectSessions) => projectSessions)
              .map(_toDomain)
              .toList()
            ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return SessionsLoaded(List.unmodifiable(sessions));
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const SessionsLoadFailed(SessionsFailure.unauthorized);
      }
      return const SessionsLoadFailed(SessionsFailure.unexpectedResponse);
    } on TimeoutException {
      return const SessionsLoadFailed(SessionsFailure.unavailable);
    } on InvalidOpenCodeOrigin {
      return const SessionsLoadFailed(SessionsFailure.unexpectedResponse);
    } on http.ClientException {
      return const SessionsLoadFailed(SessionsFailure.unavailable);
    } on FormatException {
      return const SessionsLoadFailed(SessionsFailure.unexpectedResponse);
    }
  }

  Future<SessionMutationResult> rename(
    ServerProfile profile,
    OpenCodeSession session,
    String title,
  ) {
    return _mutate(
      () async => _sessionsService.renameSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        session,
        title,
      ),
    );
  }

  Future<SessionMutationResult> delete(
    ServerProfile profile,
    OpenCodeSession session,
  ) {
    return _mutate(
      () async => _sessionsService.deleteSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        session,
      ),
    );
  }

  Future<SessionMutationResult> _mutate(Future<void> Function() action) async {
    try {
      await action();
      return const Ok(null);
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const Err(SessionsFailure.unauthorized);
      }
      return const Err(SessionsFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    }
  }

  OpenCodeSession _toDomain(OpenCodeSessionRecord record) {
    return OpenCodeSession(
      id: record.id,
      projectId: record.projectId,
      directory: record.directory,
      title: record.title,
      createdAt: DateTime.fromMillisecondsSinceEpoch(record.createdAtMillis),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(record.updatedAtMillis),
      parentId: record.parentId,
      changedFiles: record.changedFiles,
      additions: record.additions,
      deletions: record.deletions,
    );
  }
}
