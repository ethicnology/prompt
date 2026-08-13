import '../../../core/async/result.dart';
import '../domain/voice_failure.dart';
import '../domain/voice_language.dart';
import 'voice_engine.dart';
import 'voice_model_picker.dart';

/// Owns the current memory-only capture. It never persists, logs, returns, or
/// transmits audio or transcripts. Every exit path releases the capture.
class VoiceRepository {
  VoiceRepository(this._engine, this._modelPicker);

  final VoiceEngine _engine;
  final VoiceModelPicker _modelPicker;
  VoiceCapture? _activeCapture;
  String? _modelPath;

  bool get hasSelectedModel => _modelPath != null;

  Future<bool> selectModelFromUserAction() async {
    final modelPath = await _modelPicker.pickModelFromUserAction();
    if (modelPath == null) return false;
    await release(releaseModel: true);
    _modelPath = modelPath;
    return true;
  }

  Future<Result<void, VoiceFailure>> prepareFromUserAction() async {
    final modelPath = _modelPath;
    if (modelPath == null) {
      return const Err(VoiceEngineUnavailable());
    }
    final permission = await _engine.requestMicrophonePermission();
    if (permission case Err<void, VoiceEngineFailure>(:final failure)) {
      return Err(_mapFailure(failure));
    }
    return const Ok(null);
  }

  Future<Result<void, VoiceFailure>> startSegment(
    VoiceLanguage language,
  ) async {
    await release();
    final modelPath = _modelPath;
    if (modelPath == null) {
      return const Err(VoiceEngineUnavailable());
    }

    final capture = await _engine.startCapture(
      modelPath: modelPath,
      language: language,
    );
    return switch (capture) {
      Ok<VoiceCapture, VoiceEngineFailure>(:final value) => () {
        _activeCapture = value;
        return const Ok<void, VoiceFailure>(null);
      }(),
      Err<VoiceCapture, VoiceEngineFailure>(:final failure) => Err(
        _mapFailure(failure),
      ),
    };
  }

  Future<void> release({bool releaseModel = false}) async {
    final capture = _activeCapture;
    _activeCapture = null;
    await capture?.release();
    if (releaseModel) {
      await _engine.releaseModel();
    }
  }

  Future<Result<String, VoiceFailure>> stop() async {
    final capture = _activeCapture;
    _activeCapture = null;
    if (capture == null) return const Err(VoiceCaptureFailed());
    try {
      final result = await capture.stop();
      return switch (result) {
        Ok(:final value) => Ok(value),
        Err(:final failure) => Err(_mapFailure(failure)),
      };
    } finally {
      await capture.release();
    }
  }

  Stream<String> get partialTranscripts =>
      _activeCapture?.partialTranscripts ?? const Stream.empty();

  VoiceFailure _mapFailure(VoiceEngineFailure failure) => switch (failure) {
    VoiceEngineFailure.permissionDenied => const VoicePermissionDenied(),
    VoiceEngineFailure.permissionUnavailable =>
      const VoicePermissionUnavailable(),
    VoiceEngineFailure.assetsNotBundled => const VoiceEngineUnavailable(),
    VoiceEngineFailure.modelUnavailable => const VoiceEngineUnavailable(),
    VoiceEngineFailure.captureFailed => const VoiceCaptureFailed(),
    VoiceEngineFailure.transcriptionFailed => const VoiceTranscriptionFailed(),
  };
}
