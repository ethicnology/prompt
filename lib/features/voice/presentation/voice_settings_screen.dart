import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/voice_language.dart';
import 'voice_view_model.dart';

/// Global local-model configuration. Recording is available only from a
/// conversation's visible composer control.
class VoiceSettingsScreen extends StatelessWidget {
  const VoiceSettingsScreen({required this.viewModel, super.key});

  final VoiceViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(viewModel.cancel());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Voice input')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Local voice transcription',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Audio and any future transcript stay in memory only. Prompt does not use remote speech-to-text.',
            ),
            const SizedBox(height: 20),
            Text(
              'Dictation language',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ValueListenableBuilder<VoiceLanguage>(
              valueListenable: viewModel.language,
              builder: (context, language, _) => SegmentedButton<VoiceLanguage>(
                segments: VoiceLanguage.values
                    .map(
                      (option) => ButtonSegment<VoiceLanguage>(
                        value: option,
                        label: Text(option.label),
                      ),
                    )
                    .toList(growable: false),
                selected: {language},
                onSelectionChanged: (selection) =>
                    viewModel.language.value = selection.single,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Download a local multilingual Whisper model, then select its '
              'file. The conversation composer will show Voice input once a '
              'model is selected. Audio and transcripts stay in memory only.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openModelDownload(
                'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
              ),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download Tiny multilingual model (fast)'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openModelDownload(
                'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
              ),
              icon: const Icon(Icons.download_outlined),
              label: const Text(
                'Download Base multilingual model (French, recommended)',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _openModelDownload(
                'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
              ),
              icon: const Icon(Icons.download_outlined),
              label: const Text(
                'Download Small multilingual model (French, more accurate)',
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: viewModel.hasSelectedModel,
              builder: (context, hasSelectedModel, _) => FilledButton.tonal(
                onPressed: viewModel.selectModelFromUserAction,
                child: Text(
                  hasSelectedModel
                      ? 'Change local Whisper model file'
                      : 'Choose local Whisper model file',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openModelDownload(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
