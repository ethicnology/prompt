import 'package:flutter/material.dart';

import '../domain/voice_language.dart';
import '../domain/voice_failure.dart';
import 'voice_view_model.dart';

class VoiceSettingsScreen extends StatelessWidget {
  const VoiceSettingsScreen({required this.viewModel, super.key});

  final VoiceViewModel viewModel;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Voice input')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Recognition language',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<VoiceLanguage>(
          valueListenable: viewModel.language,
          builder: (context, language, _) =>
              DropdownButtonFormField<VoiceLanguage>(
                initialValue: language,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Language',
                ),
                items: [
                  for (final option in VoiceLanguage.values)
                    DropdownMenuItem(value: option, child: Text(option.label)),
                ],
                onChanged: (value) {
                  if (value != null) viewModel.selectLanguage(value);
                },
              ),
        ),
        const SizedBox(height: 20),
        Text(
          'Local Sherpa models',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Install downloads, verifies, stores, and selects all four required '
          'files in one action. French needs about 123 MiB; English needs about '
          '69 MiB. Models remain installed across app updates. Installing '
          'explicitly contacts Hugging Face to download the selected model.',
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<Set<VoiceLanguage>>(
          valueListenable: viewModel.selectedModelLanguages,
          builder: (context, selected, _) =>
              ValueListenableBuilder<Map<VoiceLanguage, double>>(
                valueListenable: viewModel.modelInstallProgress,
                builder: (context, progress, _) =>
                    ValueListenableBuilder<
                      Map<VoiceLanguage, VoiceModelInstallFailure>
                    >(
                      valueListenable: viewModel.modelInstallFailures,
                      builder: (context, failures, _) => Column(
                        children: [
                          _ModelCard(
                            language: VoiceLanguage.french,
                            selected: selected.contains(VoiceLanguage.french),
                            progress: progress[VoiceLanguage.french],
                            failure: failures[VoiceLanguage.french],
                            onInstall: () =>
                                viewModel.installModelFromUserAction(
                                  VoiceLanguage.french,
                                ),
                            onRemove: () => viewModel.removeModelFromUserAction(
                              VoiceLanguage.french,
                            ),
                            onSelectExisting: () =>
                                viewModel.selectModelFromUserAction(
                                  VoiceLanguage.french,
                                ),
                          ),
                          const SizedBox(height: 12),
                          _ModelCard(
                            language: VoiceLanguage.english,
                            selected: selected.contains(VoiceLanguage.english),
                            progress: progress[VoiceLanguage.english],
                            failure: failures[VoiceLanguage.english],
                            onInstall: () =>
                                viewModel.installModelFromUserAction(
                                  VoiceLanguage.english,
                                ),
                            onRemove: () => viewModel.removeModelFromUserAction(
                              VoiceLanguage.english,
                            ),
                            onSelectExisting: () =>
                                viewModel.selectModelFromUserAction(
                                  VoiceLanguage.english,
                                ),
                          ),
                        ],
                      ),
                    ),
              ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Models and transcripts remain local. Audio stays in memory and is '
          'released after each segment, cancellation, or lifecycle pause. '
          'Removing a model deletes its private files.',
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.language,
    required this.selected,
    required this.progress,
    required this.failure,
    required this.onInstall,
    required this.onRemove,
    required this.onSelectExisting,
  });

  final VoiceLanguage language;
  final bool selected;
  final double? progress;
  final VoiceModelInstallFailure? failure;
  final VoidCallback onInstall;
  final VoidCallback onRemove;
  final VoidCallback onSelectExisting;

  @override
  Widget build(BuildContext context) {
    final installing = progress != null;
    final status = installing
        ? 'Installing ${(progress! * 100).round()}%'
        : selected
        ? 'Installed'
        : failure != null
        ? failure!.message
        : 'Not installed';
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${language.label} INT8',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(status),
              ],
            ),
            if (installing) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: installing ? null : onInstall,
              icon: const Icon(Icons.download_outlined),
              label: Text(
                '${selected ? 'Reinstall' : 'Install'} ${language.label} model',
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: installing ? null : onRemove,
                icon: const Icon(Icons.delete_outline),
                label: Text('Remove ${language.label} model'),
              ),
            ],
            const SizedBox(height: 4),
            TextButton(
              onPressed: installing ? null : onSelectExisting,
              child: Text('Choose existing ${language.label} model files'),
            ),
          ],
        ),
      ),
    );
  }
}
