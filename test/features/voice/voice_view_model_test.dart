import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/features/voice/data/voice_engine.dart';
import 'package:prompt/features/voice/data/voice_repository.dart';
import 'package:prompt/features/voice/data/voice_model_picker.dart';
import 'package:prompt/features/voice/domain/voice_failure.dart';
import 'package:prompt/features/voice/domain/voice_language.dart';
import 'package:prompt/features/voice/domain/voice_model.dart';
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

    await viewModel.selectModelFromUserAction(VoiceLanguage.french);
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

    await viewModel.selectModelFromUserAction(VoiceLanguage.french);
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

  test(
    'release flushes the bounded segment and keeps voice mode ready',
    () async {
      final capture = _FakeCapture(transcript: 'local transcript');
      final viewModel = VoiceViewModel(
        VoiceRepository(_FakeVoiceEngine(capture: capture), _FakeModelPicker()),
      );

      await viewModel.selectModelFromUserAction(VoiceLanguage.french);
      await viewModel.enterModeFromUserAction();
      expect(viewModel.state.value, isA<VoiceReady>());
      await viewModel.startSegmentFromUserAction();
      await viewModel.finishSegmentFromUserAction();

      expect(viewModel.state.value, isA<VoiceReady>());
      expect(
        (viewModel.state.value as VoiceReady).transcript,
        'local transcript',
      );
      expect(capture.stopCalls, 1);
      expect(capture.releaseCalls, 1);
      await viewModel.stopModeFromUserAction();
      expect(capture.stopCalls, 1);
      expect(capture.releaseCalls, 1);
      await viewModel.dispose();
    },
  );

  test(
    'keeps applying partials while final transcription catches up',
    () async {
      final stopCompleter = Completer<Result<String, VoiceEngineFailure>>();
      final capture = _FakeCapture(stopResult: stopCompleter.future);
      final viewModel = VoiceViewModel(
        VoiceRepository(_FakeVoiceEngine(capture: capture), _FakeModelPicker()),
      );

      await viewModel.selectModelFromUserAction(VoiceLanguage.french);
      await viewModel.enterModeFromUserAction();
      await viewModel.startSegmentFromUserAction();
      capture.partials.add('first words');
      await Future<void>.delayed(Duration.zero);
      final stopping = viewModel.stopModeFromUserAction();
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
      expect(viewModel.state.value, isA<VoiceIdle>());
      await viewModel.dispose();
    },
  );

  test(
    'exposes finalize failure instead of discarding the partial transcript',
    () async {
      final capture = _FakeCapture(transcript: 'partial transcript');
      final engine = _FakeVoiceEngine(
        capture: capture,
        finalizeResult: const Err(VoiceEngineFailure.transcriptionFailed),
      );
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, _FakeModelPicker()),
      );

      await viewModel.selectModelFromUserAction(VoiceLanguage.french);
      await viewModel.enterModeFromUserAction();
      await viewModel.startSegmentFromUserAction();
      await viewModel.finishSegmentFromUserAction();

      await viewModel.stopModeFromUserAction();

      expect(viewModel.state.value, isA<VoiceUnavailable>());
      expect(
        (viewModel.state.value as VoiceUnavailable).failure,
        isA<VoiceTranscriptionFailed>(),
      );
      expect(capture.releaseCalls, 1);
      expect(engine.releaseModelCalls, 2);
      await viewModel.dispose();
    },
  );

  test('configures the explicitly selected language model', () async {
    final engine = _FakeVoiceEngine(capture: _FakeCapture());
    final viewModel = VoiceViewModel(
      VoiceRepository(engine, _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction(VoiceLanguage.french);
    await viewModel.enterModeFromUserAction();
    await viewModel.startSegmentFromUserAction();

    expect(engine.selectedLanguage, VoiceLanguage.french);
    expect(engine.selectedLanguage?.code, 'fr');
    await viewModel.dispose();
  });

  test('enables voice only when the current language has a model', () async {
    final viewModel = VoiceViewModel(
      VoiceRepository(_FakeVoiceEngine(), _FakeModelPicker()),
    );

    await viewModel.selectModelFromUserAction(VoiceLanguage.french);
    expect(viewModel.hasSelectedModel.value, isTrue);

    viewModel.selectLanguage(VoiceLanguage.english);
    expect(viewModel.hasSelectedModel.value, isFalse);

    await viewModel.selectModelFromUserAction(VoiceLanguage.english);
    expect(viewModel.hasSelectedModel.value, isTrue);
    expect(viewModel.selectedModelLanguages.value, {
      VoiceLanguage.french,
      VoiceLanguage.english,
    });
    await viewModel.dispose();
  });

  test(
    'keeps voice mode ready between segments and releases model on stop',
    () async {
      final first = _FakeCapture(transcript: 'FIRST');
      final second = _FakeCapture(transcript: 'SECOND');
      final engine = _FakeVoiceEngine(
        captures: [first, second],
        finalizedTranscript: 'GLOBALLY CORRECTED',
      );
      final publishedTranscripts = <String>[];
      final viewModel = VoiceViewModel(
        VoiceRepository(engine, _FakeModelPicker()),
      );
      viewModel.state.addListener(() {
        if (viewModel.state.value case VoiceReady(:final transcript)) {
          publishedTranscripts.add(transcript);
        }
      });

      await viewModel.selectModelFromUserAction(VoiceLanguage.french);
      await viewModel.enterModeFromUserAction();
      expect(viewModel.state.value, isA<VoiceReady>());

      await viewModel.startSegmentFromUserAction();
      first.partials.add('FIRST');
      await Future<void>.delayed(Duration.zero);
      await viewModel.finishSegmentFromUserAction();
      expect((viewModel.state.value as VoiceReady).transcript, 'first');
      await viewModel.startSegmentFromUserAction();
      second.partials.add('SECOND');
      await Future<void>.delayed(Duration.zero);
      await viewModel.finishSegmentFromUserAction();
      expect((viewModel.state.value as VoiceReady).transcript, 'first second');
      expect(engine.permissionRequests, 1);
      expect(engine.captureRequests, 2);
      expect(first.stopCalls, 1);
      expect(second.stopCalls, 1);

      await viewModel.stopModeFromUserAction();
      expect(viewModel.state.value, isA<VoiceIdle>());
      expect(engine.finalizeModeCalls, 1);
      expect(publishedTranscripts, contains('globally corrected'));
      // Selecting prepares a clean engine, and leaving voice mode releases the
      // heavy recognizer instead of keeping it resident in the app.
      expect(engine.releaseModelCalls, 2);
      await viewModel.dispose();
      expect(engine.releaseModelCalls, 3);
    },
  );

  test(
    'a release during capture start flushes as soon as capture is ready',
    () async {
      final startingCapture =
          Completer<Result<VoiceCapture, VoiceEngineFailure>>();
      final capture = _FakeCapture(transcript: 'short phrase');
      final viewModel = VoiceViewModel(
        VoiceRepository(
          _FakeVoiceEngine(startCaptureResult: startingCapture.future),
          _FakeModelPicker(),
        ),
      );
      await viewModel.selectModelFromUserAction(VoiceLanguage.french);
      await viewModel.enterModeFromUserAction();

      final starting = viewModel.startSegmentFromUserAction();
      await Future<void>.delayed(Duration.zero);
      await viewModel.finishSegmentFromUserAction();
      startingCapture.complete(Ok(capture));
      await starting;

      expect(viewModel.state.value, isA<VoiceReady>());
      expect(capture.stopCalls, 1);
      await viewModel.dispose();
    },
  );
}

class _FakeVoiceEngine implements VoiceEngine {
  _FakeVoiceEngine({
    this.permissionResult = const Ok(null),
    this.capture,
    this.captures,
    this.startCaptureResult,
    this.finalizedTranscript = '',
    this.finalizeResult,
  });

  final Result<void, VoiceEngineFailure> permissionResult;
  final _FakeCapture? capture;
  final List<_FakeCapture>? captures;
  final Future<Result<VoiceCapture, VoiceEngineFailure>>? startCaptureResult;
  final String finalizedTranscript;
  final Result<String, VoiceEngineFailure>? finalizeResult;
  var permissionRequests = 0;
  var captureRequests = 0;
  VoiceLanguage? selectedLanguage;
  var releaseModelCalls = 0;
  var finalizeModeCalls = 0;

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    permissionRequests++;
    return permissionResult;
  }

  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async => const Ok(null);

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async {
    captureRequests++;
    selectedLanguage = model.language;
    final pending = startCaptureResult;
    if (pending != null) return pending;
    final value = captures?.removeAt(0) ?? capture;
    if (value == null) return const Err(VoiceEngineFailure.captureFailed);
    return Ok(value);
  }

  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async {
    finalizeModeCalls++;
    return finalizeResult ?? Ok(finalizedTranscript);
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
  var stopCalls = 0;

  @override
  Stream<String> get partialTranscripts => partials.stream;

  @override
  Future<Result<String, VoiceEngineFailure>> stop() async {
    stopCalls++;
    final result =
        await (stopResult ??
            Future<Result<String, VoiceEngineFailure>>.value(Ok(transcript)));
    if (!partials.isClosed) {
      await partials.close();
    }
    return result;
  }

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
  Future<VoiceModel?> pickModelFromUserAction(VoiceLanguage language) async =>
      _model(language);
}

VoiceModel _model(VoiceLanguage language) => VoiceModel(
  language: language,
  encoderPath: '/encoder.int8.onnx',
  decoderPath: '/decoder.onnx',
  joinerPath: '/joiner.int8.onnx',
  tokensPath: '/tokens.txt',
  modelType: language == VoiceLanguage.french ? 'zipformer' : 'zipformer2',
);
