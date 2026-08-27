import 'package:flutter/foundation.dart';

import '../../../core/async/result.dart';
import '../../../data/remote/opencode_session_status_parser.dart';
import '../../connection/connection.dart';
import '../data/sessions_repository.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_activity.dart';
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
  const SessionsReady(
    this.sessions,
    this.projects, {
    this.activities = const <String, SessionActivity>{},
    this.unavailableDirectories = const <String>{},
  });

  final List<OpenCodeSession> sessions;
  final List<OpenCodeProject> projects;
  final Map<String, SessionActivity> activities;
  final Set<String> unavailableDirectories;
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
  int _suggestionRevision = 0;
  ValueListenable<Map<String, OpenCodeSessionStatus>>? _liveStatuses;
  Map<String, SessionActivity> _liveActivities = const {};
  Map<String, SessionActivity> _baseActivities = const {};

  /// Binds the coordinator's existing global SSE status feed. Binding is
  /// presentation-only: this view model never starts network work.
  void bindLiveStatuses(
    ValueListenable<Map<String, OpenCodeSessionStatus>> statuses,
  ) {
    if (identical(_liveStatuses, statuses)) {
      return;
    }
    unbindLiveStatuses();
    _liveStatuses = statuses;
    _liveActivities = _toActivities(statuses.value);
    statuses.addListener(_onLiveStatusesChanged);
    _overlayCurrentState();
  }

  void unbindLiveStatuses() {
    final statuses = _liveStatuses;
    if (statuses == null) {
      return;
    }
    statuses.removeListener(_onLiveStatusesChanged);
    _liveStatuses = null;
    _liveActivities = const {};
    _overlayCurrentState();
  }

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
      case SessionsLoaded(
        :final sessions,
        :final projects,
        :final activities,
        :final unavailableDirectories,
      ):
        _baseActivities = Map.unmodifiable(activities);
        value = sessions.isEmpty
            ? SessionsReady(
                const [],
                projects,
                activities: _overlayActivities(activities),
                unavailableDirectories: unavailableDirectories,
              )
            : SessionsReady(
                sessions,
                projects,
                activities: _overlayActivities(activities),
                unavailableDirectories: unavailableDirectories,
              );
      case SessionsLoadFailed(:final failure):
        value = SessionsError(failure);
    }
  }

  Future<Result<OpenCodeSession, SessionsFailure>> create(
    ServerProfile profile,
    String directory, {
    String? title,
  }) async {
    final revision = ++_revision;
    final result = await _repository.create(
      profile,
      directory.trim(),
      title: title,
    );
    if (revision == _revision) {
      if (result case Ok<OpenCodeSession, SessionsFailure>(:final value)) {
        _addSession(value);
      }
    }
    return result;
  }

  Future<Result<List<String>, SessionsFailure>?> suggestDirectories(
    ServerProfile profile,
    String input,
  ) async {
    final revision = ++_suggestionRevision;
    final result = await _repository.suggestDirectories(profile, input);
    return revision == _suggestionRevision ? result : null;
  }

  void _onLiveStatusesChanged() {
    final statuses = _liveStatuses;
    if (statuses == null) return;
    _liveActivities = _toActivities(statuses.value);
    _overlayCurrentState();
  }

  Map<String, SessionActivity> _toActivities(
    Map<String, OpenCodeSessionStatus> statuses,
  ) => {
    for (final entry in statuses.entries)
      entry.key: switch (entry.value) {
        OpenCodeSessionStatusBusy() => SessionActivity.working,
        OpenCodeSessionStatusIdle() => SessionActivity.idle,
        OpenCodeSessionStatusRetry() => SessionActivity.retrying,
        OpenCodeSessionStatusUnknown() => SessionActivity.unknown,
      },
  };

  Map<String, SessionActivity> _overlayActivities(
    Map<String, SessionActivity> activities,
  ) => Map.unmodifiable({...activities, ..._liveActivities});

  void _overlayCurrentState() {
    if (value case SessionsReady(
      :final sessions,
      :final projects,
      :final unavailableDirectories,
    )) {
      value = SessionsReady(
        sessions,
        projects,
        activities: _overlayActivities(_baseActivities),
        unavailableDirectories: unavailableDirectories,
      );
    }
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
          modelProviderId: session.modelProviderId,
          modelId: session.modelId,
          agentName: session.agentName,
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
      if (value case SessionsReady(
        :final sessions,
        :final projects,
        :final unavailableDirectories,
      )) {
        final nextActivities = Map<String, SessionActivity>.from(
          _baseActivities,
        )..remove(session.id);
        _baseActivities = Map.unmodifiable(nextActivities);
        value = SessionsReady(
          List.unmodifiable(
            sessions.where((candidate) => candidate.id != session.id),
          ),
          projects,
          activities: _overlayActivities(_baseActivities),
          unavailableDirectories: unavailableDirectories,
        );
      }
    }
    return null;
  }

  void _addSession(OpenCodeSession session) {
    if (value case SessionsReady(
      :final sessions,
      :final projects,
      :final unavailableDirectories,
    )) {
      final updated = [
        session,
        ...sessions.where((candidate) => candidate.id != session.id),
      ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      value = SessionsReady(
        List.unmodifiable(updated),
        projects,
        activities: _overlayActivities(_baseActivities),
        unavailableDirectories: unavailableDirectories,
      );
    }
  }

  void _replaceSession(OpenCodeSession previous, OpenCodeSession replacement) {
    if (value case SessionsReady(
      :final sessions,
      :final projects,
      :final unavailableDirectories,
    )) {
      final updated = [
        for (final session in sessions)
          if (session.id == previous.id) replacement else session,
      ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      value = SessionsReady(
        List.unmodifiable(updated),
        projects,
        activities: _overlayActivities(_baseActivities),
        unavailableDirectories: unavailableDirectories,
      );
    }
  }

  @override
  void dispose() {
    unbindLiveStatuses();
    super.dispose();
  }
}
