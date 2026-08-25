import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:stt_lab/audio_input.dart';

void main() {
  test('decodes mono PCM16 16 kHz WAV fixtures', () {
    final bytes = _wav([0, 16384, -16384]);

    final decoded = decodePcm16Wav(bytes);

    expect(decoded.samples, hasLength(3));
    expect(decoded.samples[0], 0);
    expect(decoded.samples[1], closeTo(0.5, 0.0001));
    expect(decoded.samples[2], closeTo(-0.5, 0.0001));
  });

  test('rejects WAV fixtures with an unsupported sample rate', () {
    expect(
      () => decodePcm16Wav(_wav([0], sampleRate: 8000)),
      throwsFormatException,
    );
  });
}

Uint8List _wav(List<int> samples, {int sampleRate = 16000}) {
  final output = Uint8List(44 + samples.length * 2);
  final data = ByteData.sublistView(output);
  output.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, output.length - 8, Endian.little);
  output.setRange(8, 12, 'WAVE'.codeUnits);
  output.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  output.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var index = 0; index < samples.length; index++) {
    data.setInt16(44 + index * 2, samples[index], Endian.little);
  }
  return output;
}
