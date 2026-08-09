import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/domain/voice_failure.dart';
import 'package:prompt/features/voice/presentation/voice_view_model.dart';

void main() {
  test(
    'does not request permission before the explicit voice action',
    () async {
      final engine = _FakeVoiceEngine();
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, _FakeModelPicker()),
      );
      expect(engine.permissionRequests, 0);
      expect(viewModel.state.value, isA<VoiceIdle>());
      await viewModel.dispose();
    },
  );

  test('reports an unavailable engine without starting capture', () async {
    final engine = _FakeVoiceEngine(
      permissionResult: const Err(VoiceEngineFailure.assetsNotBundled),
    );
    final viewModel = VoiceViewModel(
      VoiceRepository(engine, _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction();
    await viewModel.startFromUserAction();

    expect(engine.permissionRequests, 1);
    expect(engine.captureRequests, 0);
    expect(viewModel.state.value, isA<VoiceUnavailable>());
    expect(
      (viewModel.state.value as VoiceUnavailable).failure,
      isA<VoiceEngineUnavailable>(),
    );
    await viewModel.dispose();
  });

  test(
    'requires a selected model before it asks for microphone permission',
    () async {
      final engine = _FakeVoiceEngine();
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, _FakeModelPicker()),
      );

      await viewModel.startFromUserAction();

      expect(engine.permissionRequests, 0);
      expect(viewModel.state.value, isA<VoiceUnavailable>());
      await viewModel.dispose();
    },
  );

  test('releases memory-only capture on inactivity and disposal', () async {
    final capture = _FakeCapture();
    final engine = _FakeVoiceEngine(capture: capture);
    final viewModel = VoiceViewModel(
      VoiceRepository(engine, _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction();
    await viewModel.startFromUserAction();
    expect(viewModel.state.value, isA<VoiceRecording>());
    await viewModel.notifyAppInactive();
    expect(capture.releaseCalls, 1);
    expect(viewModel.state.value, isA<VoiceIdle>());

    await viewModel.startFromUserAction();
    await viewModel.dispose();
    expect(capture.releaseCalls, 2);
  });

  test('stops, returns the local transcript, and releases capture', () async {
    final capture = _FakeCapture(transcript: 'local transcript');
    final viewModel = VoiceViewModel(
      VoiceRepository(_FakeVoiceEngine(capture: capture), _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction();
    await viewModel.startFromUserAction();
    await viewModel.stopFromUserAction();

    expect(viewModel.state.value, isA<VoiceTranscriptReady>());
    expect(
      (viewModel.state.value as VoiceTranscriptReady).transcript,
      'local transcript',
    );
    expect(capture.releaseCalls, 1);
    await viewModel.dispose();
  });
}

class _FakeVoiceEngine implements VoiceEngine {
  _FakeVoiceEngine({this.permissionResult = const Ok(null), this.capture});

  final Result<void, VoiceEngineFailure> permissionResult;
  final _FakeCapture? capture;
  var permissionRequests = 0;
  var captureRequests = 0;

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    permissionRequests++;
    return permissionResult;
  }

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture(
    String modelPath,
  ) async {
    captureRequests++;
    final value = capture;
    if (value == null) return const Err(VoiceEngineFailure.captureFailed);
    return Ok(value);
  }
}

class _FakeCapture implements VoiceCapture {
  _FakeCapture({this.transcript = ''});

  final String transcript;
  var releaseCalls = 0;

  @override
  Stream<String> get partialTranscripts => const Stream.empty();

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async => Ok(transcript);

  @override
  Future<void> release() async {
    releaseCalls++;
  }
}

class _FakeModelPicker implements VoiceModelPicker {
  @override
  Future<String?> pickModelFromUserAction() async => '/model.bin';
}
