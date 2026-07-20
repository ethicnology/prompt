/// Bounded exponential backoff with jitter for a reconnecting stream
/// connection. This is a reusable technical primitive: it knows nothing
/// about OpenCode, SSE, or sessions, and performs no I/O, timers, or
/// logging of its own. A caller schedules the delay this returns however
/// it prefers (a real `Timer` in production, an injectable fake in tests).
library;

import 'dart:math' as math;

/// Computes the delay before each reconnect attempt and whether a caller
/// should keep retrying at all.
///
/// Attempt numbers are 1-based: attempt `1` is the first retry after an
/// initial connection drops, not the initial connection itself.
class ReconnectBackoffPolicy {
  const ReconnectBackoffPolicy({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 6,
    this.jitterFraction = 0.5,
  }) : assert(maxAttempts > 0, 'maxAttempts must allow at least one retry'),
       assert(
         jitterFraction >= 0 && jitterFraction <= 1,
         'jitterFraction must be between 0 and 1',
       );

  /// The delay before the first retry attempt, before jitter.
  final Duration initialDelay;

  /// The delay never grows past this, before jitter is added.
  final Duration maxDelay;

  /// Retrying stops once [shouldRetry] has reported `false` for an
  /// attempt; a permanently unreachable server does not retry forever
  /// while the app stays foreground.
  final int maxAttempts;

  /// The maximum extra fraction of the base delay added as jitter, so
  /// many clients reconnecting after the same outage do not retry in
  /// lockstep. `0.5` means up to +50% on top of the doubled base delay.
  final double jitterFraction;

  /// Whether [attempt] (1-based) should still be retried.
  bool shouldRetry(int attempt) => attempt <= maxAttempts;

  /// The delay before [attempt] (1-based), doubling from [initialDelay],
  /// capped at [maxDelay], with up to [jitterFraction] extra added by
  /// [random]. [random] is required, rather than internally constructed,
  /// so a caller can seed it for deterministic tests.
  Duration delayForAttempt(int attempt, math.Random random) {
    assert(attempt >= 1, 'attempt is 1-based');
    final exponent = attempt - 1;
    final scaledMillis =
        initialDelay.inMilliseconds * math.pow(2, exponent).toDouble();
    final cappedMillis = math.min(
      scaledMillis,
      maxDelay.inMilliseconds.toDouble(),
    );
    final jitterMultiplier = 1 + random.nextDouble() * jitterFraction;
    final withJitterMillis = (cappedMillis * jitterMultiplier).round();
    return Duration(
      milliseconds: withJitterMillis.clamp(0, maxDelay.inMilliseconds),
    );
  }
}
