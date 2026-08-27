/// Defensive parser for OpenCode session execution status payloads.
library;

/// A valid execution update extracted from a global SSE envelope.
final class OpenCodeGlobalSessionStatus {
  const OpenCodeGlobalSessionStatus({
    required this.sessionId,
    required this.status,
  });

  final String sessionId;
  final OpenCodeSessionStatus status;
}

sealed class OpenCodeSessionStatus {
  const OpenCodeSessionStatus();
}

final class OpenCodeSessionStatusUnknown extends OpenCodeSessionStatus {
  const OpenCodeSessionStatusUnknown();
}

final class OpenCodeSessionStatusBusy extends OpenCodeSessionStatus {
  const OpenCodeSessionStatusBusy();
}

final class OpenCodeSessionStatusIdle extends OpenCodeSessionStatus {
  const OpenCodeSessionStatusIdle();
}

final class OpenCodeSessionStatusRetry extends OpenCodeSessionStatus {
  const OpenCodeSessionStatusRetry({
    required this.attempt,
    required this.message,
    required this.next,
  });

  final int attempt;
  final String message;
  final int next;
}

/// Parses one `busy`, `idle`, or `retry` status without throwing.
OpenCodeSessionStatus parseOpenCodeSessionStatus(Object? value) {
  if (value is! Map<String, dynamic>) {
    return const OpenCodeSessionStatusUnknown();
  }
  return switch (value['type']) {
    'busy' => const OpenCodeSessionStatusBusy(),
    'idle' => const OpenCodeSessionStatusIdle(),
    'retry' => _parseRetry(value),
    _ => const OpenCodeSessionStatusUnknown(),
  };
}

/// Extracts a session execution update from a global event payload.
///
/// Global events carry their fields in `properties`. Unknown and malformed
/// events return `null` so they cannot affect either the catalog or chat.
OpenCodeGlobalSessionStatus? parseOpenCodeGlobalSessionStatus(
  Map<String, dynamic> payload,
) {
  final properties = payload['properties'];
  if (properties is! Map<String, dynamic>) {
    return null;
  }
  final sessionId = properties['sessionID'];
  if (sessionId is! String || sessionId.isEmpty) {
    return null;
  }
  final status = switch (payload['type']) {
    'session.status' => parseOpenCodeSessionStatus(properties['status']),
    'session.idle' => const OpenCodeSessionStatusIdle(),
    _ => const OpenCodeSessionStatusUnknown(),
  };
  if (status is OpenCodeSessionStatusUnknown) {
    return null;
  }
  return OpenCodeGlobalSessionStatus(sessionId: sessionId, status: status);
}

OpenCodeSessionStatus _parseRetry(Map<String, dynamic> value) {
  final attempt = value['attempt'];
  final message = value['message'];
  final next = value['next'];
  if (attempt is! num || message is! String || next is! num) {
    return const OpenCodeSessionStatusUnknown();
  }
  return OpenCodeSessionStatusRetry(
    attempt: attempt.toInt(),
    message: message,
    next: next.toInt(),
  );
}
