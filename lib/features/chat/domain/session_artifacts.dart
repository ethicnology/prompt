/// A task reported by OpenCode for a session.
class SessionTodo {
  const SessionTodo({
    required this.content,
    required this.status,
    required this.priority,
    this.id,
  });

  /// OpenCode's `Todo` schema carries no identifier; it stays `null` unless a
  /// server version starts sending one.
  final String? id;
  final String content;
  final SessionTodoStatus status;
  final SessionTodoPriority priority;
}

enum SessionTodoStatus { pending, inProgress, completed, cancelled }

enum SessionTodoPriority { high, medium, low }

/// A file-level change reported by OpenCode for a session.
class SessionFileDiff {
  const SessionFileDiff({
    required this.file,
    required this.patch,
    required this.additions,
    required this.deletions,
    this.status,
  });

  final String file;

  /// The unified patch OpenCode reports for this file. Empty when the server
  /// only reports the change counters.
  final String patch;
  final int additions;
  final int deletions;

  /// `added`, `modified`, or `deleted` when the server reports it.
  final String? status;
}

sealed class SessionArtifactsState {
  const SessionArtifactsState();
}

class SessionArtifactsLoading extends SessionArtifactsState {
  const SessionArtifactsLoading();
}

class SessionArtifactsReady extends SessionArtifactsState {
  const SessionArtifactsReady({required this.todos, required this.diffs});

  final List<SessionTodo> todos;
  final List<SessionFileDiff> diffs;
}

class SessionArtifactsError extends SessionArtifactsState {
  const SessionArtifactsError(this.failure);

  final SessionArtifactsFailure failure;
}

enum SessionArtifactsFailure { unauthorized, unavailable, unexpectedResponse }

extension SessionArtifactsFailureMessage on SessionArtifactsFailure {
  String get message {
    return switch (this) {
      SessionArtifactsFailure.unauthorized =>
        'The server rejected the saved credentials.',
      SessionArtifactsFailure.unavailable =>
        'Prompt cannot reach the server. Check WireGuard and try again.',
      SessionArtifactsFailure.unexpectedResponse =>
        'The server returned session artifacts Prompt could not read.',
    };
  }
}
