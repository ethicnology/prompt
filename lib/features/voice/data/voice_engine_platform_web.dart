import 'voice_engine.dart';
import 'voice_engine_platform_stub.dart';

VoiceEngine createVoiceEngine() => const WebVoiceEngineStub();

/// The browser adapter remains unavailable until a measured Web model is
/// bundled; it never calls browser media APIs in this state.
class WebVoiceEngineStub extends UnsupportedVoiceEngine {
  const WebVoiceEngineStub();
}
