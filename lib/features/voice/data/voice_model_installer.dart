import '../domain/voice_language.dart';
import '../domain/voice_model.dart';

typedef VoiceModelInstallProgress = void Function(double progress);

sealed class VoiceModelInstallException implements Exception {
  const VoiceModelInstallException();
}

class VoiceModelHttpException extends VoiceModelInstallException {
  const VoiceModelHttpException();
}

class VoiceModelNetworkException extends VoiceModelInstallException {
  const VoiceModelNetworkException();
}

class VoiceModelSizeException extends VoiceModelInstallException {
  const VoiceModelSizeException();
}

class VoiceModelChecksumException extends VoiceModelInstallException {
  const VoiceModelChecksumException();
}

class VoiceModelStorageException extends VoiceModelInstallException {
  const VoiceModelStorageException();
}

class VoiceModelCancelledException extends VoiceModelInstallException {
  const VoiceModelCancelledException();
}

class VoiceModelUnavailableException extends VoiceModelInstallException {
  const VoiceModelUnavailableException();
}

class VoiceModelInstallExceptionUnexpected extends VoiceModelInstallException {
  const VoiceModelInstallExceptionUnexpected();
}

abstract interface class VoiceModelInstaller {
  Future<VoiceModel?> installedModel(VoiceLanguage language);

  Future<VoiceModel> install(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  });

  Future<void> remove(VoiceLanguage language);
}
