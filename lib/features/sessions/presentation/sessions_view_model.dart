import 'package:flutter/foundation.dart';

import '../../connection/domain/server_profile.dart';
import '../data/sessions_repository.dart';
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
  const SessionsReady(this.sessions);

  final List<OpenCodeSession> sessions;
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
      case SessionsLoaded(:final sessions):
        value = sessions.isEmpty
            ? const SessionsEmpty()
            : SessionsReady(sessions);
      case SessionsLoadFailed(:final failure):
        value = SessionsError(failure);
    }
  }
}
