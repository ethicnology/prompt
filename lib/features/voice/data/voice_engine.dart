import '../../../core/async/result.dart';
import '../domain/voice_model.dart';

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

  Future<Result<String, VoiceEngineFailure>> stop();

  Future<void> release();
}

/// Platform boundary for local capture and Sherpa transcription.
///
/// `requestMicrophonePermission` is intentionally separate and may only be
/// called from a direct user action in a view model. No implementation sends
/// audio or transcripts over the network.
abstract interface class VoiceEngine {
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission();

  Future<Result<void, VoiceEngineFailure>> prepareModel(VoiceModel model);

  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  });

  /// Re-decodes every completed segment as one memory-only utterance.
  Future<Result<String, VoiceEngineFailure>> finalizeMode();

  /// Releases the model retained between short dictation segments.
  Future<void> releaseModel();
}
