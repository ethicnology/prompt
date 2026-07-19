sealed class ConnectionResult {
  const ConnectionResult();
}

class ConnectionSucceeded extends ConnectionResult {
  const ConnectionSucceeded();
}

class ConnectionFailed extends ConnectionResult {
  const ConnectionFailed(this.failure);

  final ConnectionFailure failure;
}

enum ConnectionFailure {
  invalidAddress,
  unauthorized,
  unavailable,
  unexpectedResponse,
}

extension ConnectionFailureMessage on ConnectionFailure {
  String get message {
    return switch (this) {
      ConnectionFailure.invalidAddress =>
        'Enter a private HTTP address or a valid HTTPS address.',
      ConnectionFailure.unauthorized =>
        'The server rejected these credentials.',
      ConnectionFailure.unavailable =>
        'Prompt cannot reach this server. Check WireGuard and the address.',
      ConnectionFailure.unexpectedResponse =>
        'The server responded, but is not ready for Prompt.',
    };
  }
}
