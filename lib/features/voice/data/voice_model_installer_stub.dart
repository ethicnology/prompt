import '../domain/voice_language.dart';
import '../domain/voice_model.dart';
import 'voice_model_installer.dart';

VoiceModelInstaller createVoiceModelInstaller() =>
    const UnsupportedVoiceModelInstaller();

class UnsupportedVoiceModelInstaller implements VoiceModelInstaller {
  const UnsupportedVoiceModelInstaller();

  @override
  Future<VoiceModel?> installedModel(VoiceLanguage language) async => null;

  @override
  Future<VoiceModel> install(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  }) => throw const VoiceModelUnavailableException();

  @override
  Future<void> remove(VoiceLanguage language) async {}
}
