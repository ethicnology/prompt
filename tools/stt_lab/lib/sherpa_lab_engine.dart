import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import 'lab_models.dart';

/// Streams audio through a long-lived isolate running a French Zipformer
/// Sherpa-ONNX streaming recognizer, then re-scores the full recording with
/// Whisper for a higher quality final transcript.
///
/// The Sherpa recognizer never runs on the UI isolate: all FFI calls happen
/// in a dedicated worker isolate spawned in [start] and torn down in [stop],
/// [cancel] or [dispose]. Communication between isolates only uses maps,
/// primitives, [SendPort]s and [TransferableTypedData], which is what the
/// Dart isolate boundary allows.
final class SherpaWhisperLabEngine implements LabEngine {
  SherpaWhisperLabEngine({required this.config, required this.useWhisperFinal});

  final EngineConfig config;
  final bool useWhisperFinal;

  final StreamController<TranscriptUpdate> _updates =
      StreamController<TranscriptUpdate>.broadcast();

  Isolate? _isolate;
  ReceivePort? _fromIsolate;
  SendPort? _toIsolate;
  StreamSubscription<Object?>? _isolateSubscription;
  StreamSubscription<RecordingChunk>? _audioSubscription;

  Completer<SendPort>? _isolateReady;
  Completer<String>? _sherpaFinal;

  Future<WhisperEngine>? _whisperEngineFuture;
  WhisperEngine? _whisperEngine;

  bool _stopping = false;
  bool _cancelled = false;

  @override
  Stream<TranscriptUpdate> get updates => _updates.stream;

  @override
  Future<void> start(Stream<RecordingChunk> audio) async {
    final modelPaths = config.sherpaModelPaths;
    if (modelPaths == null) {
      throw StateError('Sherpa model paths are required for this variant');
    }

    // Load Whisper in parallel with the Sherpa isolate startup so the final
    // quality pass does not wait on disk/model init after streaming ends.
    if (useWhisperFinal) {
      _whisperEngineFuture = WhisperEngine.load(
        config.whisperModelPath,
        config: const WhisperConfig(useGpu: true, useFlashAttention: true),
      )..then((engine) => _whisperEngine = engine);
    }

    final ready = Completer<SendPort>();
    _isolateReady = ready;
    final fromIsolate = ReceivePort();
    _fromIsolate = fromIsolate;

    _isolateSubscription = fromIsolate.listen(_handleIsolateMessage);

    _isolate = await Isolate.spawn(
      _sherpaIsolateMain,
      _IsolateStartMessage(
        mainSendPort: fromIsolate.sendPort,
        encoderPath: modelPaths.encoder,
        decoderPath: modelPaths.decoder,
        joinerPath: modelPaths.joiner,
        tokensPath: modelPaths.tokens,
        modelType: modelPaths.modelType,
      ),
    );

    final workerSendPort = await ready.future;
    _toIsolate = workerSendPort;

    _audioSubscription = audio.listen((chunk) {
      if (_stopping || _cancelled) return;
      final port = _toIsolate;
      if (port == null) return;
      port.send(
        _ChunkMessage(
          sampleRate: chunk.sampleRate,
          data: TransferableTypedData.fromList([chunk.samples]),
        ),
      );
    }, onError: _updates.addError);
  }

  void _handleIsolateMessage(Object? message) {
    if (message is SendPort) {
      _isolateReady?.complete(message);
      return;
    }
    if (message is _UpdateMessage) {
      _updates.add(
        TranscriptUpdate(
          confirmed: message.confirmed,
          provisional: message.provisional,
        ),
      );
      return;
    }
    if (message is _FinalMessage) {
      _sherpaFinal?.complete(message.text);
      return;
    }
    if (message is _ErrorMessage) {
      _updates.addError(StateError(message.reason));
      _sherpaFinal?.completeError(StateError(message.reason));
      return;
    }
  }

  @override
  Future<String> stop(Float32List completeAudio) async {
    _stopping = true;
    await _audioSubscription?.cancel();

    final finalCompleter = Completer<String>();
    _sherpaFinal = finalCompleter;
    _toIsolate?.send(const _StopMessage());

    var sherpaFinalText = '';
    try {
      sherpaFinalText = await finalCompleter.future;
    } on Object {
      sherpaFinalText = '';
    }
    _updates.add(TranscriptUpdate(confirmed: sherpaFinalText, provisional: ''));

    await _shutdownIsolate();

    if (!useWhisperFinal || completeAudio.isEmpty) {
      return sherpaFinalText;
    }

    final engine = _whisperEngine ?? await _whisperEngineFuture;
    if (engine == null) return sherpaFinalText;

    final context = config.context.trim();
    final task = engine.transcribe(
      completeAudio,
      options: TranscribeOptions(
        language: config.language,
        threads: 4,
        strategy: WhisperSamplingStrategy.greedy,
        greedyBestOf: 5,
        tokenTimestamps: true,
        splitOnWord: true,
        suppressBlank: true,
        suppressNonSpeechTokens: true,
        initialPrompt: context.isEmpty ? null : context,
      ),
    );
    final result = await task.result;
    final finalText = result.text.trim();
    _updates.add(
      TranscriptUpdate(confirmed: finalText, provisional: '', isFinal: true),
    );
    return finalText;
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await _audioSubscription?.cancel();
    _toIsolate?.send(const _CancelMessage());
    await _shutdownIsolate();
  }

  @override
  Future<void> dispose() async {
    await _audioSubscription?.cancel();
    if (_isolate != null) {
      _toIsolate?.send(const _CancelMessage());
      await _shutdownIsolate();
    }
    _whisperEngine?.dispose();
    (await _safeWhisperFuture())?.dispose();
    await _updates.close();
  }

  Future<WhisperEngine?> _safeWhisperFuture() async {
    if (_whisperEngine != null) return null;
    try {
      return await _whisperEngineFuture;
    } on Object {
      return null;
    }
  }

  Future<void> _shutdownIsolate() async {
    await _isolateSubscription?.cancel();
    _isolateSubscription = null;
    _fromIsolate?.close();
    _fromIsolate = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
  }
}

final class _IsolateStartMessage {
  const _IsolateStartMessage({
    required this.mainSendPort,
    required this.encoderPath,
    required this.decoderPath,
    required this.joinerPath,
    required this.tokensPath,
    required this.modelType,
  });

  final SendPort mainSendPort;
  final String encoderPath;
  final String decoderPath;
  final String joinerPath;
  final String tokensPath;
  final String modelType;
}

final class _ChunkMessage {
  const _ChunkMessage({required this.sampleRate, required this.data});

  final int sampleRate;
  final TransferableTypedData data;
}

final class _StopMessage {
  const _StopMessage();
}

final class _CancelMessage {
  const _CancelMessage();
}

final class _UpdateMessage {
  const _UpdateMessage({required this.confirmed, required this.provisional});

  final String confirmed;
  final String provisional;
}

final class _FinalMessage {
  const _FinalMessage(this.text);

  final String text;
}

final class _ErrorMessage {
  const _ErrorMessage(this.reason);

  final String reason;
}

/// Entry point for the Sherpa worker isolate. Runs entirely off the UI
/// isolate: model init, FFI decoding and buffer materialization all happen
/// here.
void _sherpaIsolateMain(_IsolateStartMessage start) {
  final commandPort = ReceivePort();
  start.mainSendPort.send(commandPort.sendPort);

  sherpa_onnx.OnlineRecognizer? recognizer;
  sherpa_onnx.OnlineStream? stream;
  final confirmed = StringBuffer();

  try {
    sherpa_onnx.initBindings();
    final config = sherpa_onnx.OnlineRecognizerConfig(
      model: sherpa_onnx.OnlineModelConfig(
        transducer: sherpa_onnx.OnlineTransducerModelConfig(
          encoder: start.encoderPath,
          decoder: start.decoderPath,
          joiner: start.joinerPath,
        ),
        tokens: start.tokensPath,
        modelType: start.modelType,
      ),
      enableEndpoint: true,
    );
    recognizer = sherpa_onnx.OnlineRecognizer(config);
    stream = recognizer.createStream();
  } on Object {
    start.mainSendPort.send(
      const _ErrorMessage('Failed to initialize the streaming recognizer'),
    );
    commandPort.close();
    return;
  }

  final activeRecognizer = recognizer;
  final activeStream = stream;

  void decodeAndPublish() {
    while (activeRecognizer.isReady(activeStream)) {
      activeRecognizer.decode(activeStream);
    }
    final partial = activeRecognizer.getResult(activeStream).text.trim();
    if (activeRecognizer.isEndpoint(activeStream)) {
      if (partial.isNotEmpty) {
        if (confirmed.isNotEmpty) confirmed.write(' ');
        confirmed.write(partial);
      }
      activeRecognizer.reset(activeStream);
      start.mainSendPort.send(
        _UpdateMessage(confirmed: confirmed.toString(), provisional: ''),
      );
    } else {
      start.mainSendPort.send(
        _UpdateMessage(confirmed: confirmed.toString(), provisional: partial),
      );
    }
  }

  void shutdown() {
    activeStream.free();
    activeRecognizer.free();
    commandPort.close();
  }

  commandPort.listen((message) {
    try {
      if (message is _ChunkMessage) {
        final buffer = message.data.materialize();
        final samples = buffer.asFloat32List();
        activeStream.acceptWaveform(
          samples: samples,
          sampleRate: message.sampleRate,
        );
        decodeAndPublish();
        return;
      }
      if (message is _StopMessage) {
        activeStream.inputFinished();
        decodeAndPublish();
        final remaining = activeRecognizer.getResult(activeStream).text.trim();
        if (remaining.isNotEmpty) {
          if (confirmed.isNotEmpty) confirmed.write(' ');
          confirmed.write(remaining);
        }
        final finalText = confirmed.toString().trim();
        start.mainSendPort.send(_FinalMessage(finalText));
        shutdown();
        return;
      }
      if (message is _CancelMessage) {
        shutdown();
        return;
      }
    } on Object {
      start.mainSendPort.send(
        const _ErrorMessage('Streaming recognition failed'),
      );
      shutdown();
    }
  });
}
