/// Pure domain model of the active session's live SSE connection, as
/// tracked by [QueueSendCoordinator][see ../data/queue_send_coordinator
/// .dart]. Carries no OpenCode JSON, prompt text, or failure detail — only
/// enough to render a connection/reconnecting indicator and to gate queue
/// dispatch while the connection is not authoritatively reconciled.
library;

/// The active session's live SSE connection status.
sealed class SseConnectionState {
  const SseConnectionState();
}

/// No session is activated, or the app is currently inactive (backgrounded,
/// hidden, or about to be paused): the SSE connection is intentionally
/// closed and no reconnect attempt is scheduled. This is also the state
/// before a session's first connection attempt has been made.
final class SseSuspended extends SseConnectionState {
  const SseSuspended();
}

/// A connection attempt for the active session's first activation (or a
/// reconnect just triggered by [QueueSendCoordinator.notifyAppForeground])
/// is in flight.
final class SseConnecting extends SseConnectionState {
  const SseConnecting();
}

/// Connected and reconciled: live events are applied normally and the
/// queue may dispatch.
final class SseConnected extends SseConnectionState {
  const SseConnected();
}

/// The stream dropped while the app was foreground and a bounded
/// exponential-backoff-with-jitter reconnect attempt is scheduled for
/// [retryAt]. [attempt] is the 1-based count of consecutive failures so
/// far. No further attempt is scheduled once the coordinator's
/// [ReconnectBackoffPolicy][see ../../../core/async/reconnect_backoff
/// .dart] stops permitting retries; see [SseDisconnected].
final class SseReconnecting extends SseConnectionState {
  const SseReconnecting({required this.attempt, required this.retryAt});

  final int attempt;
  final DateTime retryAt;
}

/// The SSE socket just reconnected; the active session's authoritative
/// status (and, for the conversation UI, its transcript) is being
/// re-fetched over REST before anything from the new connection is
/// trusted. Queue dispatch stays blocked for the whole window: a missed
/// event during the drop must never let a stale local view send or skip a
/// prompt.
final class SseReconciling extends SseConnectionState {
  const SseReconciling();
}

/// Every bounded reconnect attempt failed while the app stayed
/// foreground; no further automatic attempt is scheduled. Recovery is
/// only ever a fresh [QueueSendCoordinator.activate] (opening/reopening
/// the conversation) or the app returning to the foreground after having
/// gone inactive.
final class SseDisconnected extends SseConnectionState {
  const SseDisconnected();
}
