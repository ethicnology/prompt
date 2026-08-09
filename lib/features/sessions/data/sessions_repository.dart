import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/async/result.dart';
import '../../../core/security/credentials_store.dart';
import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../domain/open_code_project.dart';
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
      // Server versions differ on whether the unscoped index includes every
      // project. Merge it with each discovered project catalog so sessions in
      // another worktree are never silently hidden. One unreachable project
      // must not hide the sessions that did load, so failures are collected
      // and only reported when nothing at all could be read.
      final byId = <String, OpenCodeSessionRecord>{};
      Object? firstFailure;
      var loadedAnyCatalog = false;
      var projects = <OpenCodeProjectRecord>[];

      Future<void> mergeCatalog(String directory) async {
        try {
          final catalog = await _sessionsService.listSessions(
            profile,
            password,
            directory,
          );
          loadedAnyCatalog = true;
          for (final session in catalog) {
            byId[session.id] = session;
          }
        } on Object catch (error) {
          firstFailure ??= error;
        }
      }

      await mergeCatalog('');
      try {
        projects = await _sessionsService.listProjects(profile, password);
      } on Object catch (error) {
        // The global index remains useful on servers that do not expose, or
        // temporarily fail, the project endpoint.
        firstFailure ??= error;
      }
      await _forEachBounded(
        projects.map((project) => project.worktree),
        mergeCatalog,
      );

      if (!loadedAnyCatalog && firstFailure != null) {
        throw firstFailure!;
      }

      final sessions = byId.values.map(_toDomain).toList()
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return SessionsLoaded(
        List.unmodifiable(sessions),
        projects: List.unmodifiable(
          projects.map(
            (project) =>
                OpenCodeProject(id: project.id, directory: project.worktree),
          ),
        ),
      );
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

  /// Runs [action] over [values] with a bounded number of in-flight requests so
  /// a large project catalog cannot open one connection per project at once.
  static Future<void> _forEachBounded(
    Iterable<String> values,
    Future<void> Function(String value) action, {
    int concurrency = 4,
  }) async {
    final pending = values.toList(growable: false);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= pending.length) {
          return;
        }
        await action(pending[index]);
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < concurrency && i < pending.length; i++) worker(),
    ];
    await Future.wait(workers);
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

  Future<SessionCreateResult> create(
    ServerProfile profile,
    OpenCodeProject project, {
    String? title,
  }) async {
    try {
      final record = await _sessionsService.createSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        project.directory,
        title: title,
      );
      return Ok(_toDomain(record));
    } on OpenCodeHttpFailure catch (failure) {
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        return const Err(SessionsFailure.unauthorized);
      }
      return const Err(SessionsFailure.unexpectedResponse);
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    } on FormatException {
      return const Err(SessionsFailure.unexpectedResponse);
    }
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

  Future<SessionCreateResult> fork(
    ServerProfile profile,
    OpenCodeSession session,
  ) => _runSession(
    () async => _toDomain(
      await _sessionsService.forkSession(
        profile,
        await _credentialsStore.readPassword(profile.id),
        session,
      ),
    ),
  );

  Future<SessionShareResult> share(
    ServerProfile profile,
    OpenCodeSession session,
  ) => _runSession(() async {
    final updated = await _sessionsService.shareSession(
      profile,
      await _credentialsStore.readPassword(profile.id),
      session,
    );
    return _safeShareUrl(updated.shareUrl);
  });

  Future<SessionMutationResult> unshare(
    ServerProfile profile,
    OpenCodeSession session,
  ) => _mutate(
    () async => _sessionsService.unshareSession(
      profile,
      await _credentialsStore.readPassword(profile.id),
      session,
    ),
  );

  Future<SessionRevertResult> revert(
    ServerProfile profile,
    OpenCodeSession session,
    String messageId,
  ) => _runSession(
    () async => _sessionsService.revertMessage(
      profile,
      await _credentialsStore.readPassword(profile.id),
      session,
      messageId,
    ),
  );

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

  Future<Result<T, SessionsFailure>> _runSession<T>(
    Future<T> Function() action,
  ) async {
    try {
      return Ok(await action());
    } on OpenCodeHttpFailure catch (failure) {
      return Err(
        failure.statusCode == 401 || failure.statusCode == 403
            ? SessionsFailure.unauthorized
            : SessionsFailure.unexpectedResponse,
      );
    } on TimeoutException {
      return const Err(SessionsFailure.unavailable);
    } on http.ClientException {
      return const Err(SessionsFailure.unavailable);
    } on FormatException {
      return const Err(SessionsFailure.unexpectedResponse);
    }
  }

  String? _safeShareUrl(String? value) {
    if (value == null) {
      return null;
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
            uri.isAbsolute &&
            uri.scheme == 'https' &&
            uri.userInfo.isEmpty
        ? uri.toString()
        : null;
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
      shareUrl: _safeShareUrl(record.shareUrl),
    );
  }
}
