import 'dart:async';

import 'package:flutter/material.dart';

import '../../capabilities/capabilities.dart';
import '../domain/review_entities.dart';
import 'review_view_model.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    required this.target,
    required this.viewModel,
    required this.capabilitiesViewModel,
    super.key,
  });

  final ReviewTarget target;
  final ReviewViewModel viewModel;
  final CapabilitiesViewModel capabilitiesViewModel;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _roles = <ReviewRole>[ReviewRole.correctness, ReviewRole.security];
  final _selection = <ReviewRole, String?>{};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.loadSnapshot(widget.target));
    widget.capabilitiesViewModel.addListener(_selectDefaults);
    _selectDefaults();
  }

  @override
  void dispose() {
    widget.capabilitiesViewModel.removeListener(_selectDefaults);
    widget.viewModel.dispose();
    super.dispose();
  }

  void _selectDefaults() {
    final state = widget.capabilitiesViewModel.value;
    if (state is! CapabilitiesReady) return;
    final models = state.capabilities.models
        .where((model) => model.isProviderConnected)
        .toList();
    final available = models.map(_modelKey).toSet();
    final used = <String>{};
    final usedProviders = <String>{};
    for (var i = 0; i < _roles.length; i++) {
      final role = _roles[i];
      final selected = _selection[role];
      if (selected != null &&
          available.contains(selected) &&
          used.add(selected)) {
        usedProviders.add(
          models.firstWhere((model) => _modelKey(model) == selected).providerId,
        );
        continue;
      }
      final candidates = models
          .where((model) => !used.contains(_modelKey(model)))
          .toList();
      OpenCodeModel? replacement;
      for (final candidate in candidates) {
        if (!usedProviders.contains(candidate.providerId)) {
          replacement = candidate;
          break;
        }
      }
      replacement ??= candidates.isEmpty ? null : candidates.first;
      final replacementKey = replacement == null
          ? null
          : _modelKey(replacement);
      _selection[role] = replacementKey;
      if (replacementKey != null) {
        used.add(replacementKey);
        usedProviders.add(replacement!.providerId);
      }
    }
    if (mounted) setState(() {});
  }

  void _addReviewer() {
    for (final role in ReviewRole.values) {
      if (!_roles.contains(role)) {
        _roles.add(role);
        _selectDefaults();
        return;
      }
    }
  }

  void _removeReviewer(ReviewRole role) {
    if (_roles.length <= 2) return;
    setState(() {
      _roles.remove(role);
      _selection.remove(role);
    });
  }

  String _role(ReviewRole role) => switch (role) {
    ReviewRole.correctness => 'Correctness',
    ReviewRole.security => 'Security',
    ReviewRole.testsAndRegressions => 'Tests & regressions',
  };

  String _passState(ReviewPassState state) => switch (state) {
    ReviewPassState.pending => 'Pending',
    ReviewPassState.running => 'Running',
    ReviewPassState.succeeded => 'Succeeded',
    ReviewPassState.failed => 'Failed',
    ReviewPassState.timedOut => 'Timed out',
    ReviewPassState.cancelled => 'Cancelled',
  };

  bool get _valid {
    final selected = _selection.values.whereType<String>().toList();
    return _roles.length >= 2 &&
        selected.length == _roles.length &&
        selected.toSet().length == _roles.length;
  }

  Future<void> _start() async {
    if (!_valid) return;
    await widget.viewModel.start(
      widget.target,
      _roles
          .map(
            (role) => ReviewReviewerConfiguration(
              role: role,
              model: ReviewModelConfiguration(
                providerId: _selection[role]!.split('\u0000').first,
                modelId: _selection[role]!
                    .split('\u0000')
                    .skip(1)
                    .join('\u0000'),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review diff')),
      body: ValueListenableBuilder<ReviewRun>(
        valueListenable: widget.viewModel,
        builder: (context, run, _) => LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _body(run),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ReviewRun run) {
    if (run.state == ReviewRunState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (run.state == ReviewRunState.failed && run.snapshot == null) {
      return _message(
        run.error?.message ?? 'Unable to load the session diff.',
        retry: true,
      );
    }
    final snapshot = run.snapshot;
    if (snapshot == null) return _message('Loading session diff…');
    if (run.state == ReviewRunState.idle) return _setup(snapshot);
    return _results(run);
  }

  Widget _message(String text, {bool retry = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, textAlign: TextAlign.center),
      if (retry) ...[
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => widget.viewModel.loadSnapshot(widget.target),
          child: const Text('Retry'),
        ),
      ],
    ],
  );

  Widget _setup(ReviewSnapshot snapshot) {
    final capabilityState = widget.capabilitiesViewModel.value;
    final models = capabilityState is CapabilitiesReady
        ? capabilityState.capabilities.models
              .where((m) => m.isProviderConnected)
              .toList()
        : const <OpenCodeModel>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Contingent review',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${snapshot.files.length} files · ${snapshot.files.fold<int>(0, (n, f) => n + _additions(f.patch))} additions · ${snapshot.files.fold<int>(0, (n, f) => n + _deletions(f.patch))} deletions',
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Privacy: the diff is sent to the providers selected below. Every result starts as a hypothesis and requires human review.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (capabilityState is CapabilitiesLoading ||
            capabilityState is CapabilitiesIdle)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading connected models',
          ),
        if (capabilityState is CapabilitiesError)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Connected models unavailable: ${capabilityState.failure.message}',
                ),
              ),
              TextButton(
                onPressed: widget.capabilitiesViewModel.retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        for (final role in _roles)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('review-selector-${role.name}'),
                    initialValue: _selection[role],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: _role(role)),
                    items: models
                        .map(
                          (model) => DropdownMenuItem(
                            value: _modelKey(model),
                            child: Text(
                              '${model.providerId} · ${model.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (model) =>
                        setState(() => _selection[role] = model),
                  ),
                ),
                if (_roles.length > 2) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('remove-reviewer-${role.name}'),
                    tooltip: 'Remove ${_role(role)} reviewer',
                    onPressed: () => _removeReviewer(role),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ],
            ),
          ),
        if (_roles.length < ReviewRole.values.length)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: models.length > _roles.length ? _addReviewer : null,
              icon: const Icon(Icons.add),
              label: const Text('Add reviewer'),
            ),
          ),
        if (_roles.length < ReviewRole.values.length)
          const SizedBox(height: 12),
        if (models.length < _roles.length)
          Text(
            'At least ${_roles.length == 2 ? 'two' : 'three'} connected models are required.',
          ),
        if (models.length >= _roles.length && !_valid)
          const Text('Select a distinct connected model for each reviewer.'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _valid ? _start : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start review'),
        ),
        const SizedBox(height: 24),
        _diff(snapshot),
      ],
    );
  }

  Widget _results(ReviewRun run) {
    final findings = [
      for (final pass in run.passes)
        for (final finding in pass.opinion?.findings ?? const <ReviewFinding>[])
          (pass.configuration.role, finding),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _runTitle(run),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (run.state == ReviewRunState.running)
              OutlinedButton(
                onPressed: widget.viewModel.cancel,
                child: const Text('Cancel'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final pass in run.passes)
          ListTile(
            leading: Icon(_icon(pass.state)),
            title: Text(_role(pass.configuration.role)),
            subtitle: Text(
              '${pass.configuration.model.providerId} · ${pass.configuration.model.modelId}'
              '${pass.error == null ? '' : '\n${pass.error!.message}'}',
            ),
            trailing: Semantics(
              label:
                  '${_role(pass.configuration.role)}: ${_passState(pass.state)}',
              liveRegion: true,
              child: Text(_passState(pass.state)),
            ),
          ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Overview')),
              ButtonSegment(value: 1, label: Text('Findings')),
              ButtonSegment(value: 2, label: Text('Opinions')),
              ButtonSegment(value: 3, label: Text('Disagreements')),
              ButtonSegment(value: 4, label: Text('Metrics')),
              ButtonSegment(value: 5, label: Text('Diff')),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          0 => _overview(run, findings.map((e) => e.$2).toList()),
          1 => _findings(findings),
          2 => _opinions(run),
          3 => _disagreements(run),
          4 => _metrics(run),
          5 => _diff(run.snapshot!),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }

  Widget _overview(ReviewRun run, List<ReviewFinding> findings) {
    if (findings.isNotEmpty) {
      final findingCount = findings.length;
      final fileCount = run.snapshot?.files.length ?? 0;
      return Text(
        '$findingCount ${findingCount == 1 ? 'hypothesis' : 'hypotheses'} across $fileCount ${fileCount == 1 ? 'file' : 'files'}.',
      );
    }
    return Text(
      run.state == ReviewRunState.completed &&
              run.passes.every((p) => p.state == ReviewPassState.succeeded)
          ? 'No findings. This is a valid positive result; all opinions completed without hypotheses.'
          : 'No findings were produced by the completed passes. The review is not an all-successful result.',
    );
  }

  Widget _opinions(ReviewRun run) => Column(
    children: [
      for (final p in run.passes)
        if (p.opinion != null)
          ListTile(
            title: Text(_role(p.configuration.role)),
            subtitle: Text(p.opinion!.summary),
          ),
    ],
  );
  Widget _disagreements(ReviewRun run) => run.disagreements.isEmpty
      ? const Text('No disagreements.')
      : Column(
          children: [
            for (final d in run.disagreements)
              Card(
                child: Text(
                  '${d.sources.length} reviewers disagree at ${d.findings.first.file}:${d.findings.first.startLine}',
                ),
              ),
          ],
        );
  Widget _metrics(ReviewRun run) => Column(
    children: [
      for (final p in run.passes)
        ListTile(
          title: Text(_role(p.configuration.role)),
          subtitle: Text(
            'Input ${p.metrics.inputTokens} · output ${p.metrics.outputTokens} · cost ${p.metrics.cost}',
          ),
        ),
    ],
  );
  Widget _findings(List<(ReviewRole, ReviewFinding)> findings) =>
      findings.isEmpty
      ? const Text('No findings.')
      : ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: findings.length,
          itemBuilder: (context, i) {
            final (role, f) = findings[i];
            return Card(
              child: ExpansionTile(
                title: Text(f.title),
                subtitle: Text(
                  '${f.severity.name.toUpperCase()} · HYPOTHESIS · ${_role(role)} · ${f.file}:${f.startLine}–${f.endLine}',
                ),
                children: [
                  ListTile(
                    title: const Text('Description'),
                    subtitle: Text(f.description),
                  ),
                  ListTile(
                    title: const Text('Anchor'),
                    subtitle: Text(
                      '${f.file}:${f.startLine}–${f.endLine} (${f.side})',
                    ),
                  ),
                  ListTile(
                    title: const Text('Role'),
                    subtitle: Text(_role(role)),
                  ),
                  ListTile(
                    title: const Text('Expected / observed'),
                    subtitle: Text(
                      '${f.expectedBehavior}\n${f.observedBehavior}',
                    ),
                  ),
                  ListTile(
                    title: const Text('Reproduction'),
                    subtitle: Text('${f.preconditions}\n${f.reproduction}'),
                  ),
                  ListTile(
                    title: const Text('Evidence'),
                    subtitle: Text(f.evidence.map((e) => e.text).join('\n')),
                  ),
                  ListTile(
                    title: const Text('Suggested test'),
                    subtitle: Text(f.suggestedTest),
                  ),
                  ListTile(
                    title: const Text('Confidence'),
                    subtitle: Text('Uncalibrated confidence: ${f.confidence}'),
                  ),
                ],
              ),
            );
          },
        );
  Widget _diff(ReviewSnapshot snapshot) => ExpansionTile(
    title: const Text('Diff'),
    children: [
      SizedBox(
        height: 320,
        child: ListView.builder(
          itemCount: snapshot.files.length,
          itemBuilder: (context, index) {
            final file = snapshot.files[index];
            return Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                '${file.path} (${file.status})\n${file.patch}',
              ),
            );
          },
        ),
      ),
    ],
  );
  IconData _icon(ReviewPassState state) => switch (state) {
    ReviewPassState.succeeded => Icons.check_circle,
    ReviewPassState.failed => Icons.error,
    ReviewPassState.timedOut => Icons.timer_off,
    ReviewPassState.cancelled => Icons.cancel,
    _ => Icons.hourglass_empty,
  };
  int _additions(String patch) => patch
      .split('\n')
      .where((l) => l.startsWith('+') && !l.startsWith('+++'))
      .length;
  int _deletions(String patch) => patch
      .split('\n')
      .where((l) => l.startsWith('-') && !l.startsWith('---'))
      .length;
  String _modelKey(OpenCodeModel model) =>
      '${model.providerId}\u0000${model.id}';
  String _runTitle(ReviewRun run) => switch (run.state) {
    ReviewRunState.running => 'Review in progress',
    ReviewRunState.completed => 'Review complete',
    ReviewRunState.partiallyFailed => 'Review partially failed',
    ReviewRunState.failed => 'Review failed',
    ReviewRunState.cancelled => 'Review cancelled',
    _ => 'Review',
  };
}
