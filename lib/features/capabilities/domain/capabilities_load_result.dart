import 'open_code_capabilities.dart';

sealed class CapabilitiesLoadResult {
  const CapabilitiesLoadResult();
}

class CapabilitiesLoaded extends CapabilitiesLoadResult {
  const CapabilitiesLoaded(this.capabilities);

  final OpenCodeCapabilities capabilities;
}

class CapabilitiesLoadFailed extends CapabilitiesLoadResult {
  const CapabilitiesLoadFailed(this.failure);

  final CapabilitiesFailure failure;
}

enum CapabilitiesFailure {
  unauthorized,
  unavailable,
  unexpectedResponse;

  String get message => switch (this) {
    CapabilitiesFailure.unauthorized =>
      'The server rejected these credentials. Reconnect and try again.',
    CapabilitiesFailure.unavailable =>
      'The server is unavailable. Check your connection and try again.',
    CapabilitiesFailure.unexpectedResponse =>
      'The server sent an unsupported capabilities response. Try again later.',
  };
}
