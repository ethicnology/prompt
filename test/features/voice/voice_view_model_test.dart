import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/domain/voice_failure.dart';
import 'package:prompt/features/voice/domain/voice_language.dart';
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
    await viewModel.enterModeFromUserAction();

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

      await viewModel.enterModeFromUserAction();

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
    await viewModel.enterModeFromUserAction();
    await viewModel.startSegmentFromUserAction();
    expect(viewModel.state.value, isA<VoiceRecording>());
    await viewModel.notifyAppInactive();
    expect(capture.releaseCalls, 1);
    expect(viewModel.state.value, isA<VoiceIdle>());

    await viewModel.enterModeFromUserAction();
    await viewModel.startSegmentFromUserAction();
    await viewModel.dispose();
    expect(capture.releaseCalls, 2);
  });

  test('stops, returns the local transcript, and releases capture', () async {
    final capture = _FakeCapture(transcript: 'local transcript');
    final viewModel = VoiceViewModel(
      VoiceRepository(_FakeVoiceEngine(capture: capture), _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction();
    await viewModel.enterModeFromUserAction();
    expect(viewModel.state.value, isA<VoiceReady>());
    await viewModel.startSegmentFromUserAction();
    await viewModel.finishSegmentFromUserAction();

    expect(viewModel.state.value, isA<VoiceReady>());
    expect(
      (viewModel.state.value as VoiceReady).transcript,
      'local transcript',
    );
    expect(capture.releaseCalls, 1);
    await viewModel.dispose();
  });

  test(
    'keeps applying partials while final transcription catches up',
    () async {
      final stopCompleter = Completer<Result<String, VoiceEngineFailure>>();
      final capture = _FakeCapture(stopResult: stopCompleter.future);
      final viewModel = VoiceViewModel(
        VoiceRepository(_FakeVoiceEngine(capture: capture), _FakeModelPicker()),
      );

      await viewModel.selectModelFromUserAction();
      await viewModel.enterModeFromUserAction();
      await viewModel.startSegmentFromUserAction();
      capture.partials.add('first words');
      await Future<void>.delayed(Duration.zero);
      final stopping = viewModel.finishSegmentFromUserAction();
      await Future<void>.delayed(Duration.zero);
      capture.partials.add('first words and last words');
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.state.value, isA<VoiceTranscribing>());
      expect(
        (viewModel.state.value as VoiceTranscribing).partialTranscript,
        'first words and last words',
      );

      stopCompleter.complete(const Ok('final transcript'));
      await stopping;
      expect(viewModel.state.value, isA<VoiceReady>());
      await viewModel.dispose();
    },
  );

  test('passes the selected dictation language to the local engine', () async {
    final engine = _FakeVoiceEngine(capture: _FakeCapture());
    final viewModel = VoiceViewModel(
      VoiceRepository(engine, _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction();
    viewModel.language.value = VoiceLanguage.english;
    await viewModel.enterModeFromUserAction();
    await viewModel.startSegmentFromUserAction();

    expect(engine.selectedLanguage, VoiceLanguage.english);
    await viewModel.dispose();
  });

  test(
    'keeps voice mode ready between segments and releases model on stop',
    () async {
      final captures = [
        _FakeCapture(transcript: 'first'),
        _FakeCapture(transcript: 'second'),
      ];
      final engine = _FakeVoiceEngine(captures: captures);
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, _FakeModelPicker()),
      );

      await viewModel.selectModelFromUserAction();
      await viewModel.enterModeFromUserAction();
      expect(viewModel.state.value, isA<VoiceReady>());

      await viewModel.startSegmentFromUserAction();
      await viewModel.finishSegmentFromUserAction();
      expect((viewModel.state.value as VoiceReady).transcript, 'first');
      await viewModel.startSegmentFromUserAction();
      await viewModel.finishSegmentFromUserAction();
      expect((viewModel.state.value as VoiceReady).transcript, 'second');
      expect(engine.permissionRequests, 1);
      expect(engine.captureRequests, 2);

      await viewModel.stopModeFromUserAction();
      expect(viewModel.state.value, isA<VoiceIdle>());
      expect(engine.releaseModelCalls, 2);
      await viewModel.dispose();
    },
  );
}

class _FakeVoiceEngine implements VoiceEngine {
  _FakeVoiceEngine({
    this.permissionResult = const Ok(null),
    this.capture,
    this.captures,
  });

  final Result<void, VoiceEngineFailure> permissionResult;
  final _FakeCapture? capture;
  final List<_FakeCapture>? captures;
  var permissionRequests = 0;
  var captureRequests = 0;
  VoiceLanguage? selectedLanguage;
  var releaseModelCalls = 0;

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    permissionRequests++;
    return permissionResult;
  }

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required String modelPath,
    required VoiceLanguage language,
  }) async {
    captureRequests++;
    selectedLanguage = language;
    final value = captures?.removeAt(0) ?? capture;
    if (value == null) return const Err(VoiceEngineFailure.captureFailed);
    return Ok(value);
  }

  @override
  Future<void> releaseModel() async {
    releaseModelCalls++;
  }
}

class _FakeCapture implements VoiceCapture {
  _FakeCapture({this.transcript = '', this.stopResult});

  final String transcript;
  final Future<Result<String, VoiceEngineFailure>>? stopResult;
  final partials = StreamController<String>.broadcast();
  var releaseCalls = 0;

  @override
  Stream<String> get partialTranscripts => partials.stream;

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async =>
      stopResult ?? Ok(transcript);

  @override
  Future<void> release() async {
    releaseCalls++;
    if (!partials.isClosed) {
      await partials.close();
    }
  }
}

class _FakeModelPicker implements VoiceModelPicker {
  @override
  Future<String?> pickModelFromUserAction() async => '/model.bin';
}
