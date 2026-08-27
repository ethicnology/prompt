import '../../../core/async/result.dart';
import 'open_code_project.dart';
import 'open_code_session.dart';
import 'session_activity.dart';

sealed class SessionLoadResult {
  const SessionLoadResult();
}

class SessionsLoaded extends SessionLoadResult {
  const SessionsLoaded(
    this.sessions, {
    this.projects = const [],
    this.activities = const <String, SessionActivity>{},
    this.unavailableDirectories = const <String>{},
  });

  final List<OpenCodeSession> sessions;
  final List<OpenCodeProject> projects;
  final Map<String, SessionActivity> activities;
  final Set<String> unavailableDirectories;
}

class SessionsLoadFailed extends SessionLoadResult {
  const SessionsLoadFailed(this.failure);

  final SessionsFailure failure;
}

enum SessionsFailure { unauthorized, unavailable, unexpectedResponse }

typedef SessionMutationResult = Result<void, SessionsFailure>;
typedef SessionCreateResult = Result<OpenCodeSession, SessionsFailure>;
typedef SessionShareResult = Result<String?, SessionsFailure>;
typedef SessionRevertResult = Result<bool, SessionsFailure>;

extension SessionsFailureMessage on SessionsFailure {
  String get message {
    return switch (this) {
      SessionsFailure.unauthorized =>
        'The server rejected the saved credentials.',
      SessionsFailure.unavailable =>
        'Prompt cannot reach the server. Check WireGuard or Tailscale and try again.',
      SessionsFailure.unexpectedResponse =>
        'The server returned sessions Prompt could not read.',
    };
  }
}
