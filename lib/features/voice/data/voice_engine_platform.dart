import 'voice_engine.dart';
import 'voice_engine_platform_stub.dart'
    if (dart.library.io) 'voice_engine_platform_native.dart'
    if (dart.library.js_interop) 'voice_engine_platform_web.dart'
    as implementation;

VoiceEngine createVoiceEngine() => implementation.createVoiceEngine();
