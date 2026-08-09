enum WorkspaceFailure { unauthorized, unavailable, unexpectedResponse }

extension WorkspaceFailureMessage on WorkspaceFailure {
  String get message => switch (this) {
    WorkspaceFailure.unauthorized =>
      'The server rejected the saved credentials.',
    WorkspaceFailure.unavailable =>
      'Prompt cannot reach the server. Check WireGuard and try again.',
    WorkspaceFailure.unexpectedResponse =>
      'The server returned workspace data Prompt could not read.',
  };
}
