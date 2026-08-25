import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_model_installer.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/domain/voice_failure.dart';
import 'package:prompt/features/voice/domain/voice_language.dart';
import 'package:prompt/features/voice/domain/voice_model.dart';

void main() {
  test(
    'maps installer exceptions to typed failures at the repository boundary',
    () async {
      final cases = <VoiceModelInstallException, Type>{
        const VoiceModelHttpException(): VoiceModelHttpFailed,
        const VoiceModelNetworkException(): VoiceModelNetworkFailed,
        const VoiceModelSizeException(): VoiceModelSizeMismatch,
        const VoiceModelChecksumException(): VoiceModelChecksumMismatch,
        const VoiceModelStorageException(): VoiceModelStorageFailed,
        const VoiceModelCancelledException(): VoiceModelInstallCancelled,
        const VoiceModelUnavailableException(): VoiceModelInstallUnavailable,
        const VoiceModelInstallExceptionUnexpected():
            VoiceModelInstallUnexpected,
      };

      for (final entry in cases.entries) {
        final result = await VoiceRepository(
          _NoopEngine(),
          _NoopPicker(),
          _ThrowingInstaller(entry.key),
        ).installModelFromUserAction(VoiceLanguage.french, onProgress: (_) {});

        expect(result, isA<Err<VoiceModel, VoiceFailure>>());
        expect(
          (result as Err<VoiceModel, VoiceFailure>).failure.runtimeType,
          entry.value,
        );
      }
    },
  );
}

class _ThrowingInstaller implements VoiceModelInstaller {
  const _ThrowingInstaller(this.error);

  final VoiceModelInstallException error;

  @override
  Future<VoiceModel?> installedModel(VoiceLanguage language) async => null;

  @override
  Future<VoiceModel> install(
    VoiceLanguage language, {
    required VoiceModelInstallProgress onProgress,
  }) => Future<VoiceModel>.error(error);

  @override
  Future<void> remove(VoiceLanguage language) async {}
}

class _NoopPicker implements VoiceModelPicker {
  @override
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language) async =>
      null;
}

class _NoopEngine implements VoiceEngine {
  @override
  Future<Result<void, VoiceEngineFailure>>
  requestMicrophonePermission() async => const Ok(null);

  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async => const Ok(null);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async => const Err(VoiceEngineFailure.captureFailed);

  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async =>
      const Ok('');

  @override
  Future<void> releaseModel() async {}
}
