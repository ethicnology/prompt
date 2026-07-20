/// Pure domain model of a session's execution state, reduced from the
/// OpenCode `session.status` and `session.idle` SSE events.
library;

/// The current execution state of one OpenCode session.
sealed class SessionExecutionState {
  const SessionExecutionState();
}

/// The session is not generating and is not waiting to retry.
final class SessionIdle extends SessionExecutionState {
  const SessionIdle();
}

/// The session is actively generating.
final class SessionBusy extends SessionExecutionState {
  const SessionBusy();
}

/// The session hit a retryable error and is waiting to attempt again.
final class SessionRetrying extends SessionExecutionState {
  const SessionRetrying({
    required this.attempt,
    required this.nextAttemptAtMillis,
  });

  /// 1-based attempt count reported by the server.
  final int attempt;

  /// Epoch milliseconds of the next scheduled attempt.
  final int nextAttemptAtMillis;
}
