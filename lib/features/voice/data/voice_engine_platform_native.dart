import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../../core/async/result.dart';
import '../domain/voice_model.dart';
import 'voice_engine.dart';
import 'voice_engine_platform_stub.dart';

VoiceEngine createVoiceEngine() => switch (Platform.operatingSystem) {
  'android' || 'ios' || 'linux' => NativeSherpaEngine(),
  _ => const UnsupportedVoiceEngine(),
};

class NativeSherpaEngine implements VoiceEngine {
  VoiceModel? _loadedModel;
  _SherpaWorker? _worker;

  @override
  Future<Result<void, VoiceEngineFailure>> requestMicrophonePermission() async {
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission()
          ? const Ok(null)
          : const Err(VoiceEngineFailure.permissionDenied);
    } on Object {
      return const Err(VoiceEngineFailure.permissionUnavailable);
    } finally {
      await recorder.dispose();
    }
  }

  @override
  Future<Result<void, VoiceEngineFailure>> prepareModel(
    VoiceModel model,
  ) async {
    if (_loadedModel == model && _worker != null) return const Ok(null);
    await releaseModel();
    try {
      final filesExist = await Future.wait(
        model.paths.map(File.new).map((file) => file.exists()),
      );
      if (filesExist.any((exists) => !exists)) {
        return const Err(VoiceEngineFailure.modelUnavailable);
      }
      _worker = await _SherpaWorker.load(model);
      _loadedModel = model;
      return const Ok(null);
    } on Object {
      await releaseModel();
      return const Err(VoiceEngineFailure.modelUnavailable);
    }
  }

  @override
  Future<Result<VoiceCapture, VoiceEngineFailure>> startCapture({
    required VoiceModel model,
  }) async {
    final worker = _worker;
    if (worker == null || _loadedModel != model) {
      return const Err(VoiceEngineFailure.modelUnavailable);
    }
    try {
      return Ok(await _NativeSherpaCapture.start(worker));
    } on Object {
      return const Err(VoiceEngineFailure.captureFailed);
    }
  }

  @override
  Future<Result<String, VoiceEngineFailure>> finalizeMode() async {
    final worker = _worker;
    if (worker == null) {
      return const Err(VoiceEngineFailure.modelUnavailable);
    }
    try {
      return Ok(await worker.finalizeMode());
    } on Object {
      return const Err(VoiceEngineFailure.transcriptionFailed);
    }
  }

  @override
  Future<void> releaseModel() async {
    final worker = _worker;
    _worker = null;
    _loadedModel = null;
    await worker?.dispose();
  }
}

class _NativeSherpaCapture implements VoiceCapture {
  _NativeSherpaCapture._(this._worker, this._recorder);

  final _SherpaWorker _worker;
  final AudioRecorder _recorder;
  final StreamController<String> _partials = StreamController.broadcast();
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<String>? _partialSubscription;
  Future<Result<String, VoiceEngineFailure>>? _stopFuture;
  bool _released = false;

  static Future<_NativeSherpaCapture> start(_SherpaWorker worker) async {
    await worker.startSegment();
    final recorder = AudioRecorder();
    final capture = _NativeSherpaCapture._(worker, recorder);
    try {
      final audio = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      capture._partialSubscription = worker.partials.listen(
        capture._partials.add,
        onError: capture._partials.addError,
      );
      capture._audioSubscription = audio.listen(
        capture._handleAudio,
        onError: capture._partials.addError,
      );
      return capture;
    } on Object {
      await recorder.dispose();
      await worker.cancelSegment();
      await capture._closeStreams();
      rethrow;
    }
  }

  @override
  Stream<String> get partialTranscripts => _partials.stream;

  void _handleAudio(Uint8List bytes) {
    if (_released) return;
    final usableBytes = bytes.lengthInBytes - bytes.lengthInBytes % 2;
    if (usableBytes == 0) return;
    final pcm = ByteData.sublistView(bytes, 0, usableBytes);
    final samples = Float32List(usableBytes ~/ 2);
    for (var index = 0; index < samples.length; index++) {
      samples[index] = pcm.getInt16(index * 2, Endian.little) / 32768.0;
    }
    _worker.addSamples(samples);
  }

  @override
  Future<Result<String, VoiceEngineFailure>> stop() => _stopFuture ??= _stop();

  Future<Result<String, VoiceEngineFailure>> _stop() async {
    if (_released) return const Err(VoiceEngineFailure.captureFailed);
    try {
      await _recorder.stop();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      final transcript = await _worker.finishSegment();
      return Ok(transcript);
    } on Object {
      return const Err(VoiceEngineFailure.transcriptionFailed);
    } finally {
      _released = true;
      await _recorder.dispose();
      await _closeStreams();
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _recorder.stop();
    } on Object {
      // The recorder may already have stopped after a platform interruption.
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _worker.cancelSegment();
    await _recorder.dispose();
    await _closeStreams();
  }

  Future<void> _closeStreams() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    if (!_partials.isClosed) await _partials.close();
  }
}

class _SherpaWorker {
  _SherpaWorker._({
    required this._isolate,
    required this._events,
    required this._eventSubscription,
    required this._commands,
  });

  final Isolate _isolate;
  final ReceivePort _events;
  final StreamSubscription<Object?> _eventSubscription;
  final SendPort _commands;
  final StreamController<String> _partials = StreamController.broadcast();
  bool _disposed = false;

  Stream<String> get partials => _partials.stream;

  static Future<_SherpaWorker> load(VoiceModel model) async {
    final events = ReceivePort();
    final ready = Completer<SendPort>();
    _SherpaWorker? worker;
    late final StreamSubscription<Object?> eventSubscription;
    eventSubscription = events.listen((message) {
      if (message is _WorkerReady && !ready.isCompleted) {
        ready.complete(message.commands);
      } else if (message is _WorkerFailure && !ready.isCompleted) {
        ready.completeError(StateError('Sherpa worker failed'));
      } else if (message is _WorkerPartial && worker != null) {
        if (!worker._partials.isClosed) worker._partials.add(message.text);
      } else if (message is _WorkerFailure && worker != null) {
        if (!worker._partials.isClosed) {
          worker._partials.addError(StateError('Sherpa worker failed'));
        }
      } else if (message == null && !ready.isCompleted) {
        ready.completeError(StateError('Sherpa worker exited'));
      } else if (message == null && worker != null && !worker._disposed) {
        if (!worker._partials.isClosed) {
          worker._partials.addError(StateError('Sherpa worker exited'));
        }
      }
    });
    final isolate = await Isolate.spawn(
      _sherpaWorkerMain,
      _WorkerStart(events.sendPort, model),
      onExit: events.sendPort,
    );
    try {
      final commands = await ready.future.timeout(const Duration(seconds: 30));
      worker = _SherpaWorker._(
        isolate: isolate,
        events: events,
        eventSubscription: eventSubscription,
        commands: commands,
      );
      return worker;
    } on Object {
      await eventSubscription.cancel();
      events.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  Future<void> startSegment() async {
    final response = await _request((reply) => _StartSegment(reply));
    if (response is! _WorkerAck) throw StateError('Could not start Sherpa');
  }

  void addSamples(Float32List samples) {
    if (_disposed) return;
    _commands.send(
      _AudioChunk(
        TransferableTypedData.fromList([
          samples.buffer.asUint8List(
            samples.offsetInBytes,
            samples.lengthInBytes,
          ),
        ]),
      ),
    );
  }

  Future<String> finishSegment() async {
    final response = await _request((reply) => _FinishSegment(reply));
    if (response case _WorkerFinal(:final text)) return text;
    throw StateError('Could not finish Sherpa');
  }

  Future<void> cancelSegment() async {
    if (_disposed) return;
    await _request((reply) => _CancelSegment(reply));
  }

  Future<String> finalizeMode() async {
    final response = await _request(
      (reply) => _FinalizeMode(reply),
      timeout: const Duration(seconds: 60),
    );
    if (response case _WorkerFinal(:final text)) return text;
    throw StateError('Could not finalize Sherpa transcription');
  }

  Future<Object?> _request(
    Object Function(SendPort) createMessage, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_disposed) throw StateError('Sherpa worker is disposed');
    final reply = ReceivePort();
    try {
      _commands.send(createMessage(reply.sendPort));
      return await reply.first.timeout(timeout);
    } finally {
      reply.close();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await _request((reply) => _DisposeWorker(reply));
    } on Object {
      // Killing the isolate below still releases all process-local handles.
    }
    _disposed = true;
    await _eventSubscription.cancel();
    _events.close();
    _isolate.kill(priority: Isolate.immediate);
    if (!_partials.isClosed) await _partials.close();
  }
}

final class _WorkerStart {
  const _WorkerStart(this.events, this.model);

  final SendPort events;
  final VoiceModel model;
}

final class _WorkerReady {
  const _WorkerReady(this.commands);

  final SendPort commands;
}

final class _StartSegment {
  const _StartSegment(this.reply);

  final SendPort reply;
}

final class _AudioChunk {
  const _AudioChunk(this.data);

  final TransferableTypedData data;
}

final class _FinishSegment {
  const _FinishSegment(this.reply);

  final SendPort reply;
}

final class _CancelSegment {
  const _CancelSegment(this.reply);

  final SendPort reply;
}

final class _FinalizeMode {
  const _FinalizeMode(this.reply);

  final SendPort reply;
}

final class _DisposeWorker {
  const _DisposeWorker(this.reply);

  final SendPort reply;
}

final class _WorkerAck {
  const _WorkerAck();
}

final class _WorkerPartial {
  const _WorkerPartial(this.text);

  final String text;
}

final class _WorkerFinal {
  const _WorkerFinal(this.text);

  final String text;
}

final class _WorkerFailure {
  const _WorkerFailure();
}

void _sherpaWorkerMain(_WorkerStart start) {
  final commands = ReceivePort();
  sherpa_onnx.OnlineRecognizer? recognizer;
  sherpa_onnx.OnlineStream? stream;
  var confirmed = '';
  var lastPublished = '';
  final modeSegments = <List<Float32List>>[];
  List<Float32List>? activeAudio;
  var retainedSampleCount = 0;
  var canRetainModeAudio = true;
  const maxRetainedSamples = 16000 * 120;

  try {
    sherpa_onnx.initBindings();
    final model = start.model;
    recognizer = sherpa_onnx.OnlineRecognizer(
      sherpa_onnx.OnlineRecognizerConfig(
        model: sherpa_onnx.OnlineModelConfig(
          transducer: sherpa_onnx.OnlineTransducerModelConfig(
            encoder: model.encoderPath,
            decoder: model.decoderPath,
            joiner: model.joinerPath,
          ),
          tokens: model.tokensPath,
          numThreads: 4,
          modelType: model.modelType,
          debug: false,
        ),
        enableEndpoint: true,
      ),
    );
  } on Object {
    start.events.send(const _WorkerFailure());
    commands.close();
    return;
  }

  final activeRecognizer = recognizer;

  String joinText(String before, String after) {
    if (before.isEmpty) return after;
    if (after.isEmpty) return before;
    return '$before $after';
  }

  void disposeStream() {
    stream?.free();
    stream = null;
    confirmed = '';
    lastPublished = '';
  }

  void wipeChunks(Iterable<Float32List> chunks) {
    for (final chunk in chunks) {
      chunk.fillRange(0, chunk.length, 0);
    }
  }

  void wipeModeAudio() {
    for (final segment in modeSegments) {
      wipeChunks(segment);
      segment.clear();
    }
    modeSegments.clear();
    final pending = activeAudio;
    if (pending != null) {
      wipeChunks(pending);
      pending.clear();
    }
    activeAudio = null;
    retainedSampleCount = 0;
  }

  String decodeModeAudio() {
    final finalStream = activeRecognizer.createStream();
    var finalConfirmed = '';

    void decode() {
      while (activeRecognizer.isReady(finalStream)) {
        activeRecognizer.decode(finalStream);
      }
      final partial = activeRecognizer.getResult(finalStream).text.trim();
      if (activeRecognizer.isEndpoint(finalStream)) {
        finalConfirmed = joinText(finalConfirmed, partial);
        activeRecognizer.reset(finalStream);
      }
    }

    try {
      for (var index = 0; index < modeSegments.length; index++) {
        if (index > 0) {
          finalStream.acceptWaveform(
            samples: Float32List(3200),
            sampleRate: 16000,
          );
          decode();
        }
        for (final chunk in modeSegments[index]) {
          finalStream.acceptWaveform(samples: chunk, sampleRate: 16000);
          decode();
        }
      }
      finalStream.inputFinished();
      decode();
      return joinText(
        finalConfirmed,
        activeRecognizer.getResult(finalStream).text.trim(),
      );
    } finally {
      finalStream.free();
    }
  }

  void decodeAndPublish() {
    final activeStream = stream;
    if (activeStream == null) return;
    while (activeRecognizer.isReady(activeStream)) {
      activeRecognizer.decode(activeStream);
    }
    final partial = activeRecognizer.getResult(activeStream).text.trim();
    if (activeRecognizer.isEndpoint(activeStream)) {
      confirmed = joinText(confirmed, partial);
      activeRecognizer.reset(activeStream);
    }
    final text = joinText(
      confirmed,
      activeRecognizer.getResult(activeStream).text.trim(),
    );
    if (text.isNotEmpty && text != lastPublished) {
      lastPublished = text;
      start.events.send(_WorkerPartial(text));
    }
  }

  start.events.send(_WorkerReady(commands.sendPort));
  commands.listen((message) {
    try {
      if (message is _StartSegment) {
        disposeStream();
        stream = activeRecognizer.createStream();
        activeAudio = <Float32List>[];
        message.reply.send(const _WorkerAck());
        return;
      }
      if (message is _AudioChunk) {
        final activeStream = stream;
        if (activeStream == null) return;
        final samples = message.data.materialize().asFloat32List();
        if (canRetainModeAudio &&
            retainedSampleCount + samples.length <= maxRetainedSamples) {
          activeAudio?.add(samples);
          retainedSampleCount += samples.length;
        } else if (canRetainModeAudio) {
          // Keep streaming beyond two minutes, but fall back to the already
          // committed segment transcripts instead of growing memory without
          // bound or replacing them from an incomplete final pass.
          wipeModeAudio();
          canRetainModeAudio = false;
        }
        activeStream.acceptWaveform(samples: samples, sampleRate: 16000);
        decodeAndPublish();
        return;
      }
      if (message is _FinishSegment) {
        final activeStream = stream;
        if (activeStream == null) {
          message.reply.send(const _WorkerFailure());
          return;
        }
        activeStream.inputFinished();
        decodeAndPublish();
        final finalText = joinText(
          confirmed,
          activeRecognizer.getResult(activeStream).text.trim(),
        );
        final completedAudio = activeAudio;
        activeAudio = null;
        if (completedAudio != null && completedAudio.isNotEmpty) {
          modeSegments.add(completedAudio);
        }
        message.reply.send(_WorkerFinal(finalText));
        disposeStream();
        return;
      }
      if (message is _CancelSegment) {
        final cancelledAudio = activeAudio;
        if (cancelledAudio != null) {
          retainedSampleCount -= cancelledAudio.fold<int>(
            0,
            (total, chunk) => total + chunk.length,
          );
          wipeChunks(cancelledAudio);
        }
        activeAudio = null;
        disposeStream();
        message.reply.send(const _WorkerAck());
        return;
      }
      if (message is _FinalizeMode) {
        final text = modeSegments.isEmpty ? '' : decodeModeAudio();
        wipeModeAudio();
        message.reply.send(_WorkerFinal(text));
        return;
      }
      if (message is _DisposeWorker) {
        disposeStream();
        wipeModeAudio();
        activeRecognizer.free();
        message.reply.send(const _WorkerAck());
        commands.close();
      }
    } on Object {
      disposeStream();
      wipeModeAudio();
      final reply = switch (message) {
        _StartSegment(:final reply) ||
        _FinishSegment(:final reply) ||
        _CancelSegment(:final reply) ||
        _FinalizeMode(:final reply) ||
        _DisposeWorker(:final reply) => reply,
        _ => null,
      };
      reply?.send(const _WorkerFailure());
      start.events.send(const _WorkerFailure());
    }
  });
}
