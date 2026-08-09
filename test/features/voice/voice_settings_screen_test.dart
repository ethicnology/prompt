import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/presentation/voice_settings_screen.dart';
import 'package:prompt/features/voice/presentation/voice_view_model.dart';

void main() {
  testWidgets(
    'selects a local model without requesting microphone permission',
    (tester) async {
      final engine = _UnavailableVoiceEngine();
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, _UnavailableModelPicker()),
      );
      await tester.pumpWidget(
        MaterialApp(home: VoiceSettingsScreen(viewModel: viewModel)),
      );

      expect(engine.permissionRequests, 0);
      await tester.tap(find.text('Choose local Whisper model file'));
      await tester.pumpAndSettle();
      expect(engine.permissionRequests, 0);
      expect(find.text('Change local Whisper model file'), findsOneWidget);
      await viewModel.dispose();
    },
  );
}

class _UnavailableVoiceEngine implements VoiceEngine {
  var permissionRequests = 0;

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    permissionRequests++;
    return const Err(VoiceEngineFailure.assetsNotBundled);
  }

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture(
    String modelPath,
  ) async => const Err(VoiceEngineFailure.assetsNotBundled);
}

class _UnavailableModelPicker implements VoiceModelPicker {
  @override
  Future<String?> pickModelFromUserAction() async => '/model.bin';
}
