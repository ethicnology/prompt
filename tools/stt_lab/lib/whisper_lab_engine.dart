import 'dart:async';
import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import 'lab_models.dart';

final class WhisperLabEngine implements LabEngine {
  WhisperLabEngine({required this.config, required this.twoPass});

  final EngineConfig config;
  final bool twoPass;
  final StreamController<TranscriptUpdate> _updates =
      StreamController<TranscriptUpdate>.broadcast();

  WhisperEngine? _engine;
  WhisperStreamTask? _task;
  StreamSubscription<WhisperStreamUpdate>? _updateSubscription;

  @override
  Stream<TranscriptUpdate> get updates => _updates.stream;

  @override
  Future<void> start(Stream<RecordingChunk> audio) async {
    final engine = await WhisperEngine.load(
      config.whisperModelPath,
      config: const WhisperConfig(useGpu: true, useFlashAttention: true),
    );
    _engine = engine;
    final task = engine.transcribeStream(
      audio,
      options: _options(bestOf: twoPass ? 1 : 5),
      config: twoPass
          ? const WhisperStreamConfig(
              updateInterval: Duration(milliseconds: 600),
              windowDuration: Duration(seconds: 10),
              confirmationLag: Duration(milliseconds: 1800),
            )
          : const WhisperStreamConfig(
              updateInterval: Duration(milliseconds: 1500),
              windowDuration: Duration(seconds: 30),
              confirmationLag: Duration(seconds: 4),
            ),
    );
    _task = task;
    _updateSubscription = task.updates.listen(
      (update) => _updates.add(
        TranscriptUpdate(
          confirmed: update.confirmedText,
          provisional: update.partialText,
          isFinal: update.isFinal,
        ),
      ),
      onError: _updates.addError,
    );
  }

  @override
  Future<String> stop(Float32List completeAudio) async {
    final streamingFinal = await _task!.stop();
    if (!twoPass || completeAudio.isEmpty) return streamingFinal.text.trim();
    final finalTask = _engine!.transcribe(
      completeAudio,
      options: _options(bestOf: 5),
    );
    final result = await finalTask.result;
    final text = result.text.trim();
    _updates.add(
      TranscriptUpdate(confirmed: text, provisional: '', isFinal: true),
    );
    return text;
  }

  TranscribeOptions _options({required int bestOf}) => TranscribeOptions(
    language: config.language,
    threads: 4,
    strategy: WhisperSamplingStrategy.greedy,
    greedyBestOf: bestOf,
    tokenTimestamps: true,
    splitOnWord: true,
    suppressBlank: true,
    suppressNonSpeechTokens: true,
    initialPrompt: config.context.trim().isEmpty ? null : config.context.trim(),
  );

  @override
  Future<void> cancel() async {
    await _task?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _updateSubscription?.cancel();
    _engine?.dispose();
    await _updates.close();
  }
}
