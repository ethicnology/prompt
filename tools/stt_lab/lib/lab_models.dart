import 'dart:async';
import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

enum LabVariant {
  whisperBaseline('Whisper baseline', 'Current quality-first rolling window'),
  whisperTwoPass(
    'Whisper two-pass',
    'Fast live hypotheses, then a quality decode on release',
  ),
  sherpaOnly(
    'Sherpa streaming',
    'True streaming with the language-specific final transcript',
  ),
  sherpaWhisper(
    'Sherpa + Whisper',
    'True streaming French Zipformer, then a Whisper final decode',
  ),
  omnilingual(
    'Omnilingual offline',
    'One automatic multilingual model decoded after release',
  );

  const LabVariant(this.label, this.description);

  final String label;
  final String description;
}

enum LabPhase {
  idle,
  loading,
  listening,
  replaying,
  finalizing,
  complete,
  failed,
}

final class TranscriptUpdate {
  const TranscriptUpdate({
    required this.confirmed,
    required this.provisional,
    this.isFinal = false,
  });

  final String confirmed;
  final String provisional;
  final bool isFinal;

  String get text => _joinText(confirmed, provisional);
}

final class SherpaModelPaths {
  const SherpaModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    this.modelType = 'zipformer',
  });

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String modelType;
}

final class OmnilingualModelPaths {
  const OmnilingualModelPaths({required this.model, required this.tokens});

  final String model;
  final String tokens;
}

final class EngineConfig {
  const EngineConfig({
    required this.whisperModelPath,
    required this.language,
    required this.context,
    this.sherpaModelPaths,
    this.omnilingualModelPaths,
  });

  final String whisperModelPath;
  final String language;
  final String context;
  final SherpaModelPaths? sherpaModelPaths;
  final OmnilingualModelPaths? omnilingualModelPaths;
}

abstract interface class LabEngine {
  Stream<TranscriptUpdate> get updates;

  Future<void> start(Stream<RecordingChunk> audio);

  Future<String> stop(Float32List completeAudio);

  Future<void> cancel();

  Future<void> dispose();
}

final class LabMetrics {
  const LabMetrics({
    this.firstPartialMs,
    this.finalizationMs,
    this.updateCount = 0,
    this.revisedWordCount = 0,
    this.streamingWordErrorRate,
    this.wordErrorRate,
  });

  final int? firstPartialMs;
  final int? finalizationMs;
  final int updateCount;
  final int revisedWordCount;
  final double? streamingWordErrorRate;
  final double? wordErrorRate;
}

final class MetricsTracker {
  final Stopwatch _clock = Stopwatch();
  int? _firstPartialMs;
  int? _stopRequestedMs;
  int _updateCount = 0;
  int _revisedWordCount = 0;
  String _previous = '';
  String _lastStreamingText = '';

  void start() {
    _clock
      ..reset()
      ..start();
  }

  void add(TranscriptUpdate update) {
    final text = update.text.trim();
    if (text.isEmpty || text == _previous) return;
    _firstPartialMs ??= _clock.elapsedMilliseconds;
    _updateCount += 1;
    _revisedWordCount += revisedWordCount(_previous, text);
    _previous = text;
    if (!update.isFinal) _lastStreamingText = text;
  }

  void markStopRequested() {
    _stopRequestedMs ??= _clock.elapsedMilliseconds;
  }

  LabMetrics finish(String finalText, String reference) {
    _clock.stop();
    return LabMetrics(
      firstPartialMs: _firstPartialMs,
      finalizationMs: _stopRequestedMs == null
          ? null
          : _clock.elapsedMilliseconds - _stopRequestedMs!,
      updateCount: _updateCount,
      revisedWordCount: _revisedWordCount,
      streamingWordErrorRate:
          reference.trim().isEmpty || _lastStreamingText.trim().isEmpty
          ? null
          : calculateWordErrorRate(reference, _lastStreamingText),
      wordErrorRate: reference.trim().isEmpty
          ? null
          : calculateWordErrorRate(reference, finalText),
    );
  }
}

int revisedWordCount(String previous, String current) {
  final before = _words(previous);
  final after = _words(current);
  var prefix = 0;
  while (prefix < before.length &&
      prefix < after.length &&
      before[prefix] == after[prefix]) {
    prefix += 1;
  }
  return before.length - prefix;
}

double calculateWordErrorRate(String reference, String hypothesis) {
  final expected = _words(reference);
  final actual = _words(hypothesis);
  if (expected.isEmpty) return actual.isEmpty ? 0 : 1;
  final previous = List<int>.generate(actual.length + 1, (index) => index);
  for (var row = 1; row <= expected.length; row++) {
    var diagonal = previous[0];
    previous[0] = row;
    for (var column = 1; column <= actual.length; column++) {
      final above = previous[column];
      final substitution =
          diagonal + (expected[row - 1] == actual[column - 1] ? 0 : 1);
      final insertion = previous[column - 1] + 1;
      final deletion = above + 1;
      previous[column] = [
        substitution,
        insertion,
        deletion,
      ].reduce((left, right) => left < right ? left : right);
      diagonal = above;
    }
  }
  return previous.last / expected.length;
}

List<String> _words(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9à-öø-ÿ'-]+"), ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

String _joinText(String left, String right) {
  final first = left.trim();
  final second = right.trim();
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;
  return '$first $second';
}
