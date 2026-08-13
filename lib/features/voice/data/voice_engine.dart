import '../../../core/async/result.dart';
import '../domain/voice_language.dart';

enum VoiceEngineFailure {
  permissionDenied,
  permissionUnavailable,
  assetsNotBundled,
  modelUnavailable,
  captureFailed,
  transcriptionFailed,
}

/// A memory-only recording owned by [VoiceRepository]. Implementations must
/// release native recorder resources and overwrite any retained audio bytes.
abstract interface class VoiceCapture {
  Stream<String> get partialTranscripts;

  Future<Result<void, VoiceEngineFailure>> resumeMicrophone();

  Future<Result<void, VoiceEngineFailure>> pauseMicrophone();

  Future<Result<String, VoiceEngineFailure>> stop();

  Future<void> release();
}

/// Platform boundary for local capture and Whisper transcription.
///
/// `requestMicrophonePermission` is intentionally separate and may only be
/// called from a direct user action in a view model. No implementation sends
/// audio or transcripts over the network.
abstract interface class VoiceEngine {
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission();

  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required String modelPath,
    required VoiceLanguage language,
  });

  /// Releases a model retained between short dictation segments.
  Future<void> releaseModel();
}
