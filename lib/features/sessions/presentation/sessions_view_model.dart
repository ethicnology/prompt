import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../connection/domain/server_profile.dart';
import '../data/sessions_repository.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';

sealed class SessionsUiState {
  const SessionsUiState();
}

class SessionsIdle extends SessionsUiState {
  const SessionsIdle();
}

class SessionsLoading extends SessionsUiState {
  const SessionsLoading();
}

class SessionsReady extends SessionsUiState {
  const SessionsReady(this.sessions, this.projects);

  final List<OpenCodeSession> sessions;
  final List<OpenCodeProject> projects;
}

class SessionsEmpty extends SessionsUiState {
  const SessionsEmpty();
}

class SessionsError extends SessionsUiState {
  const SessionsError(this.failure);

  final SessionsFailure failure;
}

class SessionsViewModel extends ValueNotifier<SessionsUiState> {
  SessionsViewModel(this._repository) : super(const SessionsIdle());

  final SessionsRepository _repository;
  int _revision = 0;

  Future<void> load(ServerProfile profile) async {
    final revision = ++_revision;
    if (value is! SessionsReady) {
      value = const SessionsLoading();
    }
    final result = await _repository.load(profile);
    if (revision != _revision) {
      return;
    }
    switch (result) {
      case SessionsLoaded(:final sessions, :final projects):
        value = sessions.isEmpty
            ? SessionsReady(const [], projects)
            : SessionsReady(sessions, projects);
      case SessionsLoadFailed(:final failure):
        value = SessionsError(failure);
    }
  }

  Future<Result<OpenCodeSession, SessionsFailure>> create(
    ServerProfile profile,
    OpenCodeProject project, {
    String? title,
  }) async {
    final revision = ++_revision;
    final result = await _repository.create(profile, project, title: title);
    if (revision == _revision) {
      if (result case Ok<OpenCodeSession, SessionsFailure>(:final value)) {
        _addSession(value);
      }
    }
    return result;
  }

  Future<SessionsFailure?> rename(
    ServerProfile profile,
    OpenCodeSession session,
    String title,
  ) async {
    final revision = ++_revision;
    final result = await _repository.rename(profile, session, title);
    if (result case Err<void, SessionsFailure>(:final failure)) {
      return failure;
    }
    if (revision == _revision) {
      _replaceSession(
        session,
        OpenCodeSession(
          id: session.id,
          projectId: session.projectId,
          directory: session.directory,
          title: title,
          createdAt: session.createdAt,
          updatedAt: DateTime.now(),
          parentId: session.parentId,
          changedFiles: session.changedFiles,
          additions: session.additions,
          deletions: session.deletions,
          shareUrl: session.shareUrl,
        ),
      );
    }
    return null;
  }

  Future<SessionsFailure?> delete(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    final revision = ++_revision;
    final result = await _repository.delete(profile, session);
    if (result case Err<void, SessionsFailure>(:final failure)) {
      return failure;
    }
    if (revision == _revision) {
      if (value case SessionsReady(:final sessions, :final projects)) {
        value = SessionsReady(
          List.unmodifiable(
            sessions.where((candidate) => candidate.id != session.id),
          ),
          projects,
        );
      }
    }
    return null;
  }

  void _addSession(OpenCodeSession session) {
    if (value case SessionsReady(:final sessions, :final projects)) {
      final updated = [
        session,
        ...sessions.where((candidate) => candidate.id != session.id),
      ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      value = SessionsReady(List.unmodifiable(updated), projects);
    }
  }

  void _replaceSession(OpenCodeSession previous, OpenCodeSession replacement) {
    if (value case SessionsReady(:final sessions, :final projects)) {
      final updated = [
        for (final session in sessions)
          if (session.id == previous.id) replacement else session,
      ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      value = SessionsReady(List.unmodifiable(updated), projects);
    }
  }
}
