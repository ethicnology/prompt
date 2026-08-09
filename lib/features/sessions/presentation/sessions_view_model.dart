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

  Future<void> load(ServerProfile profile) async {
    value = const SessionsLoading();
    final result = await _repository.load(profile);
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
    final result = await _repository.create(profile, project, title: title);
    if (result case Ok<OpenCodeSession, SessionsFailure>()) {
      await load(profile);
    }
    return result;
  }

  Future<SessionsFailure?> rename(
    ServerProfile profile,
    OpenCodeSession session,
    String title,
  ) async {
    final result = await _repository.rename(profile, session, title);
    if (result case Err<void, SessionsFailure>(:final failure)) {
      return failure;
    }
    await load(profile);
    return null;
  }

  Future<SessionsFailure?> delete(
    ServerProfile profile,
    OpenCodeSession session,
  ) async {
    final result = await _repository.delete(profile, session);
    if (result case Err<void, SessionsFailure>(:final failure)) {
      return failure;
    }
    await load(profile);
    return null;
  }
}
