import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stt_lab/lab_controller.dart';
import 'package:stt_lab/lab_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('benchmarks local engines without retaining transcripts', (
    tester,
  ) async {
    const root = String.fromEnvironment('STT_MODEL_ROOT');
    const measuredRuns = int.fromEnvironment('STT_RUNS', defaultValue: 3);
    const warmupRuns = int.fromEnvironment('STT_WARMUP_RUNS', defaultValue: 1);
    expect(root, isNotEmpty, reason: 'Pass STT_MODEL_ROOT with --dart-define');
    expect(measuredRuns, greaterThan(0));
    expect(warmupRuns, greaterThanOrEqualTo(0));
    final reports = <Map<String, Object?>>[];
    final controller = LabController();
    try {
      for (var run = -warmupRuns; run < measuredRuns; run++) {
        for (final fixture in _fixtures(root)) {
          await controller.loadWav(fixture.wavPath);
          for (final variant in LabVariant.values) {
            controller.configureModels(
              whisperModelPath: '$root/whisper.bin',
              sherpaModelPaths: fixture.sherpa,
              omnilingualModelPaths: OmnilingualModelPaths(
                model: '$root/omnilingual/model.int8.onnx',
                tokens: '$root/omnilingual/tokens.txt',
              ),
            );
            controller.selectLanguage(fixture.language);
            controller.selectVariant(variant);
            await controller.replayWav(
              context: fixture.context,
              reference: fixture.reference,
            );
            final metrics = controller.metrics;
            if (run >= 0) {
              reports.add({
                'run': run + 1,
                'language': fixture.language,
                'variant': variant.name,
                'phase': controller.phase.name,
                'firstPartialMs': metrics.firstPartialMs,
                'finalizationMs': metrics.finalizationMs,
                'updateCount': metrics.updateCount,
                'revisedWordCount': metrics.revisedWordCount,
                'streamingWordErrorRate': metrics.streamingWordErrorRate,
                'wordErrorRate': metrics.wordErrorRate,
              });
            }
            expect(controller.phase, LabPhase.complete);
            expect(metrics.firstPartialMs, isNotNull);
            expect(metrics.wordErrorRate, isNotNull);
          }
        }
      }
    } finally {
      final reportFile = File('$root/report.json');
      await reportFile.writeAsString(jsonEncode(reports), flush: true);
      controller.dispose();
    }
  });
}

List<_Fixture> _fixtures(String root) => [
  _Fixture(
    language: 'fr',
    wavPath: '$root/fixtures/fr.wav',
    reference:
        'CE SITE CONTIENT QUATRE TOMBEAUX DE LA DYNASTIE ACHÉMÉNIDE ET SEPT DES SASSANIDES',
    context: 'français, dynastie achéménide, Sassanides',
    sherpa: SherpaModelPaths(
      encoder: '$root/sherpa-fr/encoder.onnx',
      decoder: '$root/sherpa-fr/decoder.onnx',
      joiner: '$root/sherpa-fr/joiner.onnx',
      tokens: '$root/sherpa-fr/tokens.txt',
    ),
  ),
  _Fixture(
    language: 'en',
    wavPath: '$root/fixtures/en.wav',
    reference:
        'AFTER EARLY NIGHTFALL THE YELLOW LAMPS WOULD LIGHT UP HERE AND THERE THE SQUALID QUARTER OF THE BROTHELS',
    context: 'English, early nightfall, squalid quarter, brothels',
    sherpa: SherpaModelPaths(
      encoder: '$root/sherpa-en/encoder.onnx',
      decoder: '$root/sherpa-en/decoder.onnx',
      joiner: '$root/sherpa-en/joiner.onnx',
      tokens: '$root/sherpa-en/tokens.txt',
      modelType: 'zipformer2',
    ),
  ),
];

final class _Fixture {
  const _Fixture({
    required this.language,
    required this.wavPath,
    required this.reference,
    required this.context,
    required this.sherpa,
  });

  final String language;
  final String wavPath;
  final String reference;
  final String context;
  final SherpaModelPaths sherpa;
}
