sealed class VoiceFailure {
  const VoiceFailure();

  String get message;
}

class VoicePermissionDenied extends VoiceFailure {
  const VoicePermissionDenied();

  @override
  String get message => 'Microphone permission was denied.';
}

class VoicePermissionUnavailable extends VoiceFailure {
  const VoicePermissionUnavailable();

  @override
  String get message =>
      'Microphone permission is unavailable on this platform.';
}

class VoiceEngineUnavailable extends VoiceFailure {
  const VoiceEngineUnavailable();

  @override
  String get message =>
      'Local voice transcription is unavailable for the selected language.';
}

class VoiceCaptureFailed extends VoiceFailure {
  const VoiceCaptureFailed();

  @override
  String get message => 'Voice capture could not start.';
}

class VoiceTranscriptionFailed extends VoiceFailure {
  const VoiceTranscriptionFailed();

  @override
  String get message => 'Local transcription could not be completed.';
}

sealed class VoiceModelInstallFailure extends VoiceFailure {
  const VoiceModelInstallFailure();
}

class VoiceModelNetworkFailed extends VoiceModelInstallFailure {
  const VoiceModelNetworkFailed();

  @override
  String get message => 'The voice model could not be downloaded.';
}

class VoiceModelHttpFailed extends VoiceModelInstallFailure {
  const VoiceModelHttpFailed();

  @override
  String get message => 'The voice model server returned an error.';
}

class VoiceModelSizeMismatch extends VoiceModelInstallFailure {
  const VoiceModelSizeMismatch();

  @override
  String get message => 'The downloaded voice model has an unexpected size.';
}

class VoiceModelChecksumMismatch extends VoiceModelInstallFailure {
  const VoiceModelChecksumMismatch();

  @override
  String get message => 'The downloaded voice model failed its checksum.';
}

class VoiceModelStorageFailed extends VoiceModelInstallFailure {
  const VoiceModelStorageFailed();

  @override
  String get message => 'The voice model could not be stored on this device.';
}

class VoiceModelInstallCancelled extends VoiceModelInstallFailure {
  const VoiceModelInstallCancelled();

  @override
  String get message => 'Voice model installation was cancelled.';
}

class VoiceModelInstallUnavailable extends VoiceModelInstallFailure {
  const VoiceModelInstallUnavailable();

  @override
  String get message =>
      'Voice model installation is unavailable on this platform.';
}

class VoiceModelInstallUnexpected extends VoiceModelInstallFailure {
  const VoiceModelInstallUnexpected();

  @override
  String get message => 'The voice model could not be installed.';
}
