import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'lab_controller.dart';
import 'lab_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const root = String.fromEnvironment('STT_MODEL_ROOT');
  const measuredRuns = int.fromEnvironment('STT_RUNS', defaultValue: 3);
  const warmupRuns = int.fromEnvironment('STT_WARMUP_RUNS', defaultValue: 1);
  const selectedVariantName = String.fromEnvironment('STT_VARIANT');
  const sherpaPrecision = String.fromEnvironment(
    'STT_SHERPA_PRECISION',
    defaultValue: 'int8',
  );
  final reportFile = File('${Directory.systemTemp.path}/stt_lab_report.json');
  final errorFile = File('${Directory.systemTemp.path}/stt_lab_error.txt');
  final reports = <Map<String, Object?>>[];
  final controller = LabController();

  try {
    if (root.isEmpty || measuredRuns < 1 || warmupRuns < 0) {
      throw StateError('Invalid benchmark configuration');
    }
    if (sherpaPrecision != 'int8' && sherpaPrecision != 'fp32') {
      throw StateError('Unknown Sherpa precision');
    }
    final variants = selectedVariantName.isEmpty
        ? LabVariant.values
        : LabVariant.values
              .where((variant) => variant.name == selectedVariantName)
              .toList(growable: false);
    if (variants.isEmpty) throw StateError('Unknown benchmark variant');
    if (await reportFile.exists()) await reportFile.delete();
    if (await errorFile.exists()) await errorFile.delete();

    for (var run = -warmupRuns; run < measuredRuns; run++) {
      for (final fixture in _fixtures(root, sherpaPrecision)) {
        await controller.loadWav(fixture.wavPath);
        for (final variant in variants) {
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
          var peakRssBytes = ProcessInfo.currentRss;
          final memorySampler = Timer.periodic(
            const Duration(milliseconds: 100),
            (_) {
              final rss = ProcessInfo.currentRss;
              if (rss > peakRssBytes) peakRssBytes = rss;
            },
          );
          try {
            await controller.replayWav(
              context: fixture.context,
              reference: fixture.reference,
            );
          } finally {
            memorySampler.cancel();
          }
          if (controller.phase != LabPhase.complete) {
            throw StateError('Benchmark variant failed');
          }
          final metrics = controller.metrics;
          if (run >= 0) {
            reports.add({
              'run': run + 1,
              'language': fixture.language,
              'variant': variant.name,
              'precision': sherpaPrecision,
              'firstPartialMs': metrics.firstPartialMs,
              'finalizationMs': metrics.finalizationMs,
              'updateCount': metrics.updateCount,
              'revisedWordCount': metrics.revisedWordCount,
              'streamingWordErrorRate': metrics.streamingWordErrorRate,
              'wordErrorRate': metrics.wordErrorRate,
              'peakRssBytes': peakRssBytes,
              'retainedRssBytes': ProcessInfo.currentRss,
            });
            await reportFile.writeAsString(jsonEncode(reports), flush: true);
          }
        }
      }
    }
  } catch (_) {
    await errorFile.writeAsString('Benchmark failed', flush: true);
  } finally {
    controller.dispose();
  }
}

List<_Fixture> _fixtures(String root, String sherpaPrecision) {
  final suffix = sherpaPrecision == 'fp32' ? '-fp32' : '';
  return [
    _Fixture(
      language: 'fr',
      wavPath: '$root/fixtures/fr-1.wav',
      reference:
          'CE SITE CONTIENT QUATRE TOMBEAUX DE LA DYNASTIE ACHÉMÉNIDE ET SEPT DES SASSANIDES',
      context: 'français, dynastie achéménide, Sassanides',
      sherpa: SherpaModelPaths(
        encoder: '$root/sherpa-fr$suffix/encoder.onnx',
        decoder: '$root/sherpa-fr$suffix/decoder.onnx',
        joiner: '$root/sherpa-fr$suffix/joiner.onnx',
        tokens: '$root/sherpa-fr$suffix/tokens.txt',
      ),
    ),
    _Fixture(
      language: 'fr',
      wavPath: '$root/fixtures/fr-2.wav',
      reference: "CE DERNIER A ÉVOLUÉ TOUT AU LONG DE L'HISTOIRE ROMAINE",
      context: 'français, histoire romaine',
      sherpa: SherpaModelPaths(
        encoder: '$root/sherpa-fr$suffix/encoder.onnx',
        decoder: '$root/sherpa-fr$suffix/decoder.onnx',
        joiner: '$root/sherpa-fr$suffix/joiner.onnx',
        tokens: '$root/sherpa-fr$suffix/tokens.txt',
      ),
    ),
    _Fixture(
      language: 'fr',
      wavPath: '$root/fixtures/fr-3.wav',
      reference:
          'SON ACTIONNAIRE MAJORITAIRE EST LE CONSEIL TERRITORIAL DE SAINT PIERRE ET MIQUELON',
      context: 'français, Saint-Pierre-et-Miquelon, conseil territorial',
      sherpa: SherpaModelPaths(
        encoder: '$root/sherpa-fr$suffix/encoder.onnx',
        decoder: '$root/sherpa-fr$suffix/decoder.onnx',
        joiner: '$root/sherpa-fr$suffix/joiner.onnx',
        tokens: '$root/sherpa-fr$suffix/tokens.txt',
      ),
    ),
    _Fixture(
      language: 'en',
      wavPath: '$root/fixtures/en-1.wav',
      reference:
          'AFTER EARLY NIGHTFALL THE YELLOW LAMPS WOULD LIGHT UP HERE AND THERE THE SQUALID QUARTER OF THE BROTHELS',
      context: 'English, early nightfall, squalid quarter, brothels',
      sherpa: SherpaModelPaths(
        encoder: '$root/sherpa-en$suffix/encoder.onnx',
        decoder: '$root/sherpa-en$suffix/decoder.onnx',
        joiner: '$root/sherpa-en$suffix/joiner.onnx',
        tokens: '$root/sherpa-en$suffix/tokens.txt',
        modelType: 'zipformer2',
      ),
    ),
    _Fixture(
      language: 'en',
      wavPath: '$root/fixtures/en-2.wav',
      reference:
          'GOD AS A DIRECT CONSEQUENCE OF THE SIN WHICH MAN THUS PUNISHED HAD GIVEN HER A LOVELY CHILD WHOSE PLACE WAS ON THAT SAME DISHONOURED BOSOM TO CONNECT HER PARENT FOR EVER WITH THE RACE AND DESCENT OF MORTALS AND TO BE FINALLY A BLESSED SOUL IN HEAVEN',
      context: 'English, Hester Prynne, dishonoured bosom',
      sherpa: SherpaModelPaths(
        encoder: '$root/sherpa-en$suffix/encoder.onnx',
        decoder: '$root/sherpa-en$suffix/decoder.onnx',
        joiner: '$root/sherpa-en$suffix/joiner.onnx',
        tokens: '$root/sherpa-en$suffix/tokens.txt',
        modelType: 'zipformer2',
      ),
    ),
  ];
}

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
