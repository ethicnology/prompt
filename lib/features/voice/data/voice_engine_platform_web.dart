import 'voice_engine.dart';
import 'voice_engine_platform_stub.dart';

VoiceEngine createVoiceEngine() => const WebWhisperEngineStub();

/// The browser adapter remains unavailable until the separately built Whisper
/// WASM module is bundled; it never calls browser media APIs in this state.
class WebWhisperEngineStub extends UnsupportedVoiceEngine {
  const WebWhisperEngineStub();
}
