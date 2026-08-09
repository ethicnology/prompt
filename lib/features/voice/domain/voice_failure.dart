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
      'Local voice transcription is unavailable because Whisper assets are not bundled.';
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
