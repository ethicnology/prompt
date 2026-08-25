import 'dart:async';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import 'lab_models.dart';

final class OmnilingualLabEngine implements LabEngine {
  OmnilingualLabEngine({required this.config});

  final EngineConfig config;
  final StreamController<TranscriptUpdate> _updates =
      StreamController.broadcast();

  static sherpa_onnx.OfflineRecognizer? _recognizer;

  @override
  Stream<TranscriptUpdate> get updates => _updates.stream;

  @override
  Future<void> start(Stream<RecordingChunk> audio) async {
    final paths = config.omnilingualModelPaths;
    if (paths == null) throw StateError('Omnilingual model is not configured');
    if (_recognizer != null) return;

    sherpa_onnx.initBindings();
    _recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          omnilingual: sherpa_onnx.OfflineOmnilingualAsrCtcModelConfig(
            model: paths.model,
          ),
          tokens: paths.tokens,
          numThreads: 4,
          debug: false,
        ),
      ),
    );
  }

  @override
  Future<String> stop(Float32List completeAudio) async {
    final recognizer = _recognizer;
    if (recognizer == null) throw StateError('Omnilingual model is not loaded');
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: completeAudio, sampleRate: 16000);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {
    if (!_updates.isClosed) await _updates.close();
  }
}
