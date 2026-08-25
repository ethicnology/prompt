import '../../../core/async/result.dart';
import '../domain/voice_model.dart';
import 'voice_engine.dart';

VoiceEngine createVoiceEngine() => const UnsupportedVoiceEngine();

class UnsupportedVoiceEngine implements VoiceEngine {
  const UnsupportedVoiceEngine();

  @override
  Future<Result<void, VoiceEngineFailure>>
  requestMicrophonePermission() async =>
      const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async => const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async => const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async =>
      const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<void> releaseModel() async {}
}
