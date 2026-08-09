import '../../../core/async/result.dart';
import 'voice_engine.dart';

VoiceEngine createVoiceEngine() => const UnsupportedVoiceEngine();

class UnsupportedVoiceEngine implements VoiceEngine {
  const UnsupportedVoiceEngine();

  @override
  Future<Result<void, VoiceEngineFailure>>
  requestMicrophonePermission() async =>
      const Err(VoiceEngineFailure.assetsNotBundled);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture(
    String modelPath,
  ) async => const Err(VoiceEngineFailure.assetsNotBundled);
}
