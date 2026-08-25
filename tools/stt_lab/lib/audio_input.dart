import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

final class DecodedWav {
  const DecodedWav(this.samples);

  final Float32List samples;
}

DecodedWav decodePcm16Wav(Uint8List bytes) {
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('Select a RIFF WAV file');
  }
  final data = ByteData.sublistView(bytes);
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? audioFormat;
  int? dataOffset;
  int? dataLength;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final length = data.getUint32(offset + 4, Endian.little);
    final payload = offset + 8;
    if (payload + length > bytes.length) break;
    if (id == 'fmt ' && length >= 16) {
      audioFormat = data.getUint16(payload, Endian.little);
      channels = data.getUint16(payload + 2, Endian.little);
      sampleRate = data.getUint32(payload + 4, Endian.little);
      bitsPerSample = data.getUint16(payload + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = payload;
      dataLength = length;
      break;
    }
    offset = payload + length + (length.isOdd ? 1 : 0);
  }
  if (audioFormat != 1 ||
      channels != 1 ||
      sampleRate != 16000 ||
      bitsPerSample != 16 ||
      dataOffset == null ||
      dataLength == null) {
    throw const FormatException('WAV must be mono PCM16 at 16 kHz');
  }
  final count = dataLength ~/ 2;
  final samples = Float32List(count);
  for (var index = 0; index < count; index++) {
    samples[index] =
        data.getInt16(dataOffset + index * 2, Endian.little) / 32768.0;
  }
  return DecodedWav(samples);
}

Float32List pcm16BytesToFloat(Uint8List bytes) {
  final sampleCount = bytes.length ~/ 2;
  final input = ByteData.sublistView(bytes);
  final output = Float32List(sampleCount);
  for (var index = 0; index < sampleCount; index++) {
    output[index] = input.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return output;
}

final class AudioRun {
  AudioRun._() : _controller = StreamController<RecordingChunk>();

  static const sampleRate = 16000;
  static const _replayChunkSamples = 1600;

  final StreamController<RecordingChunk> _controller;
  final List<Float32List> _chunks = [];
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _recordingSubscription;
  bool _stopRequested = false;
  bool _closed = false;

  Stream<RecordingChunk> get stream => _controller.stream;

  static AudioRun create() => AudioRun._();

  Future<void> startMicrophone() async {
    final recorder = AudioRecorder();
    _recorder = recorder;
    if (!await recorder.hasPermission()) {
      throw StateError('Microphone permission was not granted');
    }
    final bytes = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );
    _recordingSubscription = bytes.listen(
      (chunk) => _add(pcm16BytesToFloat(chunk)),
      onError: _controller.addError,
      onDone: _close,
    );
  }

  Future<void> replay(Float32List samples) async {
    var offset = 0;
    while (!_stopRequested && offset < samples.length) {
      final end = (offset + _replayChunkSamples).clamp(0, samples.length);
      _add(Float32List.sublistView(samples, offset, end));
      offset = end;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _close();
  }

  Future<Float32List> stop() async {
    _stopRequested = true;
    await _recorder?.stop();
    await _recordingSubscription?.cancel();
    await _close();
    return completeAudio;
  }

  Float32List get completeAudio {
    final length = _chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Float32List(length);
    var offset = 0;
    for (final chunk in _chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  void _add(Float32List samples) {
    if (_closed || samples.isEmpty) return;
    final copy = Float32List.fromList(samples);
    _chunks.add(copy);
    _controller.add(RecordingChunk(copy, sampleRate));
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
  }
}
