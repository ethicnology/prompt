import '../../../core/async/result.dart';
import '../domain/voice_failure.dart';
import '../domain/voice_language.dart';
import '../domain/voice_model.dart';
import 'voice_engine.dart';
import 'voice_model_installer.dart';
import 'voice_model_picker.dart';

/// Owns the current memory-only capture. It never persists, logs, returns, or
/// transmits audio or transcripts. Every exit path releases the capture.
class VoiceRepository {
  VoiceRepository(this._engine, this._modelPicker, [this._modelInstaller]);

  final VoiceEngine _engine;
  final VoiceModelPicker _modelPicker;
  final VoiceModelInstaller? _modelInstaller;
  VoiceCapture? _activeCapture;
  final Map<VoiceLanguage, VoiceModel> _models = {};

  bool hasSelectedModel(VoiceLanguage language) =>
      _models.containsKey(language);

  Future<Set<VoiceLanguage>> restoreInstalledModels() async {
    final installer = _modelInstaller;
    if (installer == null) return _models.keys.toSet();
    for (final language in VoiceLanguage.values) {
      try {
        final model = await installer.installedModel(language);
        if (model != null) _models[language] = model;
      } on Object {
        // A corrupt or inaccessible installation is treated as absent. The
        // next explicit install will replace it through the typed boundary.
      }
    }
    return _models.keys.toSet();
  }

  Future<Result<VoiceModel, VoiceFailure>> installModelFromUserAction(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  }) async {
    final installer = _modelInstaller;
    if (installer == null) return const Err(VoiceModelInstallUnavailable());
    await release(releaseModel: true);
    try {
      final model = await installer.install(language, onProgress: onProgress);
      _models[language] = model;
      return Ok(model);
    } on VoiceModelHttpException {
      return const Err(VoiceModelHttpFailed());
    } on VoiceModelNetworkException {
      return const Err(VoiceModelNetworkFailed());
    } on VoiceModelSizeException {
      return const Err(VoiceModelSizeMismatch());
    } on VoiceModelChecksumException {
      return const Err(VoiceModelChecksumMismatch());
    } on VoiceModelStorageException {
      return const Err(VoiceModelStorageFailed());
    } on VoiceModelCancelledException {
      return const Err(VoiceModelInstallCancelled());
    } on VoiceModelUnavailableException {
      return const Err(VoiceModelInstallUnavailable());
    } on Object {
      return const Err(VoiceModelInstallUnexpected());
    }
  }

  Future<void> removeModel(VoiceLanguage language) async {
    await release(releaseModel: true);
    await _modelInstaller?.remove(language);
    _models.remove(language);
  }

  Future<bool> selectModelFromUserAction(VoiceLanguage language) async {
    final model = await _modelPicker.pickModelFromUserAction(language);
    if (model == null) return false;
    await release(releaseModel: true);
    _models[language] = model;
    return true;
  }

  Future<Result<void, VoiceFailure>> prepareFromUserAction(
    VoiceLanguage language,
  ) async {
    await release();
    final model = _models[language];
    if (model == null) {
      return const Err(VoiceEngineUnavailable());
    }
    final permission = await _engine.requestMicrophonePermission();
    if (permission case Err<void, VoiceEngineFailure>(:final failure)) {
      return Err(_mapFailure(failure));
    }
    final prepared = await _engine.prepareModel(model);
    return switch (prepared) {
      Ok() => const Ok(null),
      Err(:final failure) => Err(_mapFailure(failure)),
    };
  }

  Future<Result<void, VoiceFailure>> startSegment(
    VoiceLanguage language,
  ) async {
    await release();
    final model = _models[language];
    if (model == null) {
      return const Err(VoiceEngineUnavailable());
    }
    final capture = await _engine.startCapture(model: model);
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

  Future<Result<String, VoiceFailure>> finalizeMode() async {
    final result = await _engine.finalizeMode();
    return switch (result) {
      Ok(:final value) => Ok(value),
      Err(:final failure) => Err(_mapFailure(failure)),
    };
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
