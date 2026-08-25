import 'package:flutter/material.dart';

import 'lab_controller.dart';
import 'lab_models.dart';

class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  late final LabController _controller;
  late final TextEditingController _contextController;
  late final TextEditingController _referenceController;

  @override
  void initState() {
    super.initState();
    _controller = LabController()..addListener(_refresh);
    _contextController = TextEditingController(
      text: 'OpenCode, Flutter, Dart, Android, GitHub, Kubernetes, WireGuard.',
    );
    _referenceController = TextEditingController();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refresh)
      ..dispose();
    _contextController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('STT LAB'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _phaseLabel(_controller.phase),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'One audio stream. Three decoding strategies.',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Use WAV replay for repeatable comparisons. Nothing is saved '
              'after the run.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _Section(
              title: '1 / ENGINE',
              child: Column(
                children: [
                  DropdownButtonFormField<LabVariant>(
                    initialValue: _controller.variant,
                    decoration: const InputDecoration(labelText: 'Variant'),
                    items: [
                      for (final variant in LabVariant.values)
                        DropdownMenuItem(
                          value: variant,
                          child: Text(variant.label),
                        ),
                    ],
                    onChanged: _controller.isRunning
                        ? null
                        : (value) {
                            if (value != null) {
                              _controller.selectVariant(value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _controller.variant.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _controller.language,
                    decoration: const InputDecoration(
                      labelText: 'Whisper language',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'fr', child: Text('French')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'auto', child: Text('Automatic')),
                    ],
                    onChanged: _controller.isRunning
                        ? null
                        : (value) {
                            if (value != null) {
                              _controller.selectLanguage(value);
                            }
                          },
                  ),
                  const SizedBox(height: 14),
                  _ModelButton(
                    label: 'Whisper GGML',
                    value: _controller.whisperModelName,
                    onPressed: _controller.isRunning
                        ? null
                        : _controller.pickWhisperModel,
                  ),
                  const SizedBox(height: 10),
                  _ModelButton(
                    label: 'Sherpa French model files',
                    value: _controller.sherpaModelName,
                    onPressed: _controller.isRunning
                        ? null
                        : _controller.pickSherpaModel,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _contextController,
                    enabled: !_controller.isRunning,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Context / technical vocabulary',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Section(
              title: '2 / INPUT',
              child: Column(
                children: [
                  TextField(
                    controller: _referenceController,
                    enabled: !_controller.isRunning,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Expected transcript (optional WER)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ModelButton(
                    label: 'PCM16 16 kHz WAV fixture',
                    value: _controller.wavName,
                    onPressed: _controller.isRunning
                        ? null
                        : _controller.pickWav,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _controller.isRunning
                              ? (_controller.phase == LabPhase.listening
                                    ? _controller.stop
                                    : null)
                              : () => _controller.startMicrophone(
                                  context: _contextController.text,
                                  reference: _referenceController.text,
                                ),
                          icon: Icon(
                            _controller.phase == LabPhase.listening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                          ),
                          label: Text(
                            _controller.phase == LabPhase.listening
                                ? 'Stop & finalize'
                                : 'Record microphone',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _controller.canReplay
                              ? () => _controller.replayWav(
                                  context: _contextController.text,
                                  reference: _referenceController.text,
                                )
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Replay WAV'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Section(
              title: '3 / LIVE HYPOTHESIS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText.rich(
                    TextSpan(
                      style: theme.textTheme.bodyLarge,
                      children: [
                        TextSpan(text: _controller.confirmed),
                        if (_controller.confirmed.isNotEmpty &&
                            _controller.provisional.isNotEmpty)
                          const TextSpan(text: ' '),
                        TextSpan(
                          text: _controller.provisional,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        if (_controller.confirmed.isEmpty &&
                            _controller.provisional.isEmpty)
                          TextSpan(
                            text: 'Waiting for speech...',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_controller.finalText.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text('FINAL', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 6),
                    SelectableText(
                      _controller.finalText,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Metrics(metrics: _controller.metrics),
            const SizedBox(height: 12),
            Text(
              _controller.status,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _controller.phase == LabPhase.failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class _ModelButton extends StatelessWidget {
  const _ModelButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String? value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(58),
      alignment: Alignment.centerLeft,
    ),
    child: Row(
      children: [
        const Icon(Icons.folder_open_rounded),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(
                value ?? 'Not selected',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.metrics});

  final LabMetrics metrics;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _MetricChip(
        label: 'First text',
        value: metrics.firstPartialMs == null
            ? '--'
            : '${metrics.firstPartialMs} ms',
      ),
      _MetricChip(
        label: 'Finalize',
        value: metrics.finalizationMs == null
            ? '--'
            : '${metrics.finalizationMs} ms',
      ),
      _MetricChip(label: 'Updates', value: '${metrics.updateCount}'),
      _MetricChip(label: 'Revised words', value: '${metrics.revisedWordCount}'),
      _MetricChip(
        label: 'WER',
        value: metrics.wordErrorRate == null
            ? '--'
            : '${(metrics.wordErrorRate! * 100).toStringAsFixed(1)}%',
      ),
    ],
  );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    label: Text(label),
  );
}

String _phaseLabel(LabPhase phase) => switch (phase) {
  LabPhase.idle => 'READY',
  LabPhase.loading => 'LOADING',
  LabPhase.listening => 'LIVE',
  LabPhase.replaying => 'REPLAY',
  LabPhase.finalizing => 'FINAL PASS',
  LabPhase.complete => 'COMPLETE',
  LabPhase.failed => 'FAILED',
};
