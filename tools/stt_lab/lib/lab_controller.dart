import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'audio_input.dart';
import 'lab_models.dart';
import 'omnilingual_lab_engine.dart';
import 'sherpa_lab_engine.dart';
import 'whisper_lab_engine.dart';

final class LabController extends ChangeNotifier {
  LabVariant variant = LabVariant.whisperBaseline;
  String language = 'fr';
  LabPhase phase = LabPhase.idle;
  String confirmed = '';
  String provisional = '';
  String finalText = '';
  String status = 'Configure models, then record or replay a WAV fixture.';
  LabMetrics metrics = const LabMetrics();
  String? whisperModelName;
  String? sherpaModelName;
  String? wavName;

  String? _whisperModelPath;
  SherpaModelPaths? _sherpaModelPaths;
  OmnilingualModelPaths? _omnilingualModelPaths;
  Float32List? _wavSamples;
  AudioRun? _audioRun;
  LabEngine? _engine;
  StreamSubscription<TranscriptUpdate>? _updatesSubscription;
  MetricsTracker? _metricsTracker;
  String _reference = '';
  bool _finalizing = false;

  bool get isRunning => switch (phase) {
    LabPhase.loading ||
    LabPhase.listening ||
    LabPhase.replaying ||
    LabPhase.finalizing => true,
    _ => false,
  };

  bool get canReplay => _wavSamples != null && !isRunning;

  void selectVariant(LabVariant value) {
    if (isRunning) return;
    variant = value;
    notifyListeners();
  }

  void selectLanguage(String value) {
    if (isRunning) return;
    language = value;
    notifyListeners();
  }

  Future<void> pickWhisperModel() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a Whisper GGML model',
      type: FileType.any,
    );
    final file = result?.files.singleOrNull;
    if (file?.path == null) return;
    _whisperModelPath = file!.path;
    whisperModelName = file.name;
    status = 'Whisper model ready.';
    notifyListeners();
  }

  Future<void> pickSherpaModel() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select encoder, decoder, joiner, and tokens',
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null) return;
    String? match(String fragment, {bool preferInt8 = false}) {
      final matches = result.files
          .where(
            (file) =>
                file.path != null && file.name.toLowerCase().contains(fragment),
          )
          .toList();
      if (matches.isEmpty) return null;
      if (preferInt8) {
        for (final file in matches) {
          if (file.name.toLowerCase().contains('int8')) return file.path;
        }
      }
      for (final file in matches) {
        if (!file.name.toLowerCase().contains('int8')) return file.path;
      }
      return matches.first.path;
    }

    final encoder = match('encoder', preferInt8: true);
    final decoder = match('decoder');
    final joiner = match('joiner', preferInt8: true);
    final tokens = result.files
        .where((file) => file.name.toLowerCase() == 'tokens.txt')
        .firstOrNull
        ?.path;
    if (encoder == null ||
        decoder == null ||
        joiner == null ||
        tokens == null) {
      status = 'Select one encoder, decoder, joiner, and tokens.txt file.';
      notifyListeners();
      return;
    }
    _sherpaModelPaths = SherpaModelPaths(
      encoder: encoder,
      decoder: decoder,
      joiner: joiner,
      tokens: tokens,
      modelType: encoder.contains('chunk-16') ? 'zipformer2' : 'zipformer',
    );
    sherpaModelName =
        'French Zipformer (${result.files.length} files selected)';
    status = 'Sherpa model ready.';
    notifyListeners();
  }

  Future<void> pickWav() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a mono PCM16 16 kHz WAV fixture',
      type: FileType.custom,
      allowedExtensions: const ['wav'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null) return;
    try {
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('WAV is unavailable');
      _wavSamples = decodePcm16Wav(bytes).samples;
      wavName = file.name;
      status =
          'WAV ready: ${(_wavSamples!.length / AudioRun.sampleRate).toStringAsFixed(1)} s.';
    } on FormatException {
      _wavSamples = null;
      wavName = null;
      status = 'WAV must be mono PCM16 at 16 kHz.';
    }
    notifyListeners();
  }

  void configureModels({
    required String whisperModelPath,
    required SherpaModelPaths sherpaModelPaths,
    required OmnilingualModelPaths omnilingualModelPaths,
  }) {
    if (isRunning) throw StateError('Cannot reconfigure a running benchmark');
    _whisperModelPath = whisperModelPath;
    _sherpaModelPaths = sherpaModelPaths;
    _omnilingualModelPaths = omnilingualModelPaths;
    whisperModelName = 'Automated fixture model';
    sherpaModelName = 'Automated streaming model';
  }

  Future<void> loadWav(String path) async {
    if (isRunning) throw StateError('Cannot replace a running fixture');
    _wavSamples = decodePcm16Wav(await File(path).readAsBytes()).samples;
    wavName = 'Automated WAV fixture';
  }

  Future<void> startMicrophone({
    required String context,
    required String reference,
  }) async {
    if (!await _begin(context: context, reference: reference)) return;
    try {
      _metricsTracker!.start();
      await _audioRun!.startMicrophone();
      phase = LabPhase.listening;
      status = 'Listening. Audio remains in memory.';
      notifyListeners();
    } catch (_) {
      await _fail('Could not start microphone capture.');
    }
  }

  Future<void> replayWav({
    required String context,
    required String reference,
  }) async {
    final samples = _wavSamples;
    if (samples == null ||
        !await _begin(context: context, reference: reference)) {
      return;
    }
    phase = LabPhase.replaying;
    status = 'Replaying fixture at real-time speed.';
    _metricsTracker!.start();
    notifyListeners();
    try {
      await _audioRun!.replay(samples);
      await _finalize();
    } catch (_) {
      await _fail('Fixture replay failed.');
    }
  }

  Future<bool> _begin({
    required String context,
    required String reference,
  }) async {
    if (isRunning) return false;
    if (_whisperModelPath == null) {
      status = 'Select a Whisper model first.';
      notifyListeners();
      return false;
    }
    if ((variant == LabVariant.sherpaOnly ||
            variant == LabVariant.sherpaWhisper) &&
        _sherpaModelPaths == null) {
      status = 'Select the four Sherpa model files first.';
      notifyListeners();
      return false;
    }
    if (variant == LabVariant.omnilingual && _omnilingualModelPaths == null) {
      status = 'Configure the Omnilingual model first.';
      notifyListeners();
      return false;
    }
    phase = LabPhase.loading;
    confirmed = '';
    provisional = '';
    finalText = '';
    metrics = const LabMetrics();
    status = 'Loading models...';
    _reference = reference;
    _finalizing = false;
    notifyListeners();

    final config = EngineConfig(
      whisperModelPath: _whisperModelPath!,
      language: language,
      context: context,
      sherpaModelPaths: _sherpaModelPaths,
      omnilingualModelPaths: _omnilingualModelPaths,
    );
    _engine = switch (variant) {
      LabVariant.whisperBaseline => WhisperLabEngine(
        config: config,
        twoPass: false,
      ),
      LabVariant.whisperTwoPass => WhisperLabEngine(
        config: config,
        twoPass: true,
      ),
      LabVariant.sherpaOnly => SherpaWhisperLabEngine(
        config: config,
        useWhisperFinal: false,
      ),
      LabVariant.sherpaWhisper => SherpaWhisperLabEngine(
        config: config,
        useWhisperFinal: true,
      ),
      LabVariant.omnilingual => OmnilingualLabEngine(config: config),
    };
    _audioRun = AudioRun.create();
    _metricsTracker = MetricsTracker();
    _updatesSubscription = _engine!.updates.listen((update) {
      confirmed = update.confirmed.trim();
      provisional = update.provisional.trim();
      _metricsTracker?.add(update);
      notifyListeners();
    }, onError: (_) => unawaited(_fail('The transcription engine failed.')));
    try {
      await _engine!.start(_audioRun!.stream);
      return true;
    } catch (_) {
      await _fail('Could not load the selected model files.');
      return false;
    }
  }

  Future<void> stop() => _finalize();

  Future<void> _finalize() async {
    if (_finalizing || _engine == null || _audioRun == null) return;
    _finalizing = true;
    _metricsTracker?.markStopRequested();
    phase = LabPhase.finalizing;
    status = 'Final quality pass...';
    notifyListeners();
    try {
      final audio = await _audioRun!.stop();
      final result = await _engine!.stop(audio);
      finalText = result.trim();
      confirmed = finalText;
      provisional = '';
      _metricsTracker?.add(
        TranscriptUpdate(confirmed: finalText, provisional: '', isFinal: true),
      );
      metrics = _metricsTracker!.finish(finalText, _reference);
      phase = LabPhase.complete;
      status = 'Run complete. Audio buffer released.';
      await _releaseRun();
      notifyListeners();
    } catch (_) {
      await _fail('Final transcription failed.');
    }
  }

  Future<void> _fail(String message) async {
    phase = LabPhase.failed;
    status = message;
    await _engine?.cancel();
    await _releaseRun();
    notifyListeners();
  }

  Future<void> _releaseRun() async {
    await _updatesSubscription?.cancel();
    _updatesSubscription = null;
    await _audioRun?.dispose();
    _audioRun = null;
    await _engine?.dispose();
    _engine = null;
    _metricsTracker = null;
    _finalizing = false;
  }

  @override
  void dispose() {
    unawaited(_releaseRun());
    super.dispose();
  }
}
