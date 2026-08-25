import 'voice_model_installer.dart';
import 'voice_model_installer_stub.dart'
    if (dart.library.io) 'voice_model_installer_native.dart'
    as platform;

VoiceModelInstaller createVoiceModelInstaller() =>
    platform.createVoiceModelInstaller();
