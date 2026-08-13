import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection/domain/server_profile.dart';
import '../../capabilities/capabilities.dart';
import '../../queue/queue.dart';
import '../../sessions/domain/open_code_session.dart';
import '../../sessions/domain/session_load_result.dart';
import '../../voice/voice.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/pending_approval.dart';
import '../domain/prompt_attachment.dart';
import '../domain/session_artifacts.dart';
import 'conversation_view_model.dart';
import 'widgets/approval_dock.dart';
import 'widgets/composer.dart';
import 'widgets/connection_status_banner.dart';
import 'widgets/queue_panel.dart';
import 'widgets/session_artifacts_panel.dart';
import 'widgets/transcript.dart';

/// The user-facing text for [state], or `null` when nothing needs
/// announcing (a healthy connection, or the app simply being inactive,
/// which the conversation screen is not visible to observe anyway).
String? _connectionBanner(SseConnectionState state) {
  return switch (state) {
    SseConnected() || SseSuspended() => null,
    SseConnecting() => 'Connecting…',
    SseReconciling() => 'Reconnected — syncing before sending resumes…',
    SseReconnecting(:final attempt) =>
      'Connection lost. Reconnecting (attempt $attempt)…',
    SseDisconnected() =>
      'Connection lost and reconnect attempts stopped. Reopen this '
          'conversation to try again.',
  };
}

/// A stable identity for [approval], used as `ApprovalDock`'s key so a
/// brand-new approval (a different permission, or a different question
/// request) always rebuilds the dock's internal selection/text state from
/// scratch, instead of carrying over stale selections from the previous
/// approval.
String _approvalKey(PendingApproval approval) {
  return switch (approval) {
    PendingPermissionApproval(:final permissionId) =>
      'permission:$permissionId',
    PendingQuestionApproval(:final requestId) => 'question:$requestId',
  };
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    required this.profile,
    required this.session,
    required this.viewModel,
    this.capabilitiesViewModel,
    this.voiceViewModel,
    this.onOpenFork,
    super.key,
  });

  final ServerProfile profile;
  final OpenCodeSession session;
  final ConversationViewModel viewModel;
  final CapabilitiesViewModel? capabilitiesViewModel;
  final VoiceViewModel? voiceViewModel;
  final ValueChanged<OpenCodeSession>? onOpenFork;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composerController = TextEditingController();
  final _transcriptController = ScrollController();
  StreamSubscription<String>? _queueErrorSubscription;
  StreamSubscription<String>? _transcriptErrorSubscription;
  bool _showJumpToLatest = false;
  late final ValueNotifier<PromptExecutionOptions> _executionOptions;
  OpenCodeSlashCommand? _selectedCommand;
  String? _voiceDraftPrefix;

  @override
  void initState() {
    super.initState();
    _executionOptions = ValueNotifier(
      PromptExecutionOptions(
        modelProviderId: widget.session.modelProviderId,
        modelId: widget.session.modelId,
        agentName: widget.session.agentName,
      ),
    );
    _transcriptController.addListener(_updateJumpToLatestVisibility);
    widget.viewModel.open(widget.profile, widget.session);
    widget.capabilitiesViewModel?.load(widget.profile);
    widget.voiceViewModel?.state.addListener(_applyVoiceState);
    _transcriptErrorSubscription = widget.viewModel.transcriptErrors.listen((
      message,
    ) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
    _queueErrorSubscription = widget.viewModel.queueErrors.listen((message) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _queueErrorSubscription?.cancel();
    _transcriptErrorSubscription?.cancel();
    widget.voiceViewModel?.state.removeListener(_applyVoiceState);
    unawaited(widget.voiceViewModel?.cancel());
    _composerController.dispose();
    _executionOptions.dispose();
    _transcriptController
      ..removeListener(_updateJumpToLatestVisibility)
      ..dispose();
    widget.viewModel.leaveSession(widget.session);
    super.dispose();
  }

  Future<void> _submitComposer() async {
    final text = _composerController.text.trim();
    final command = _selectedCommand;
    final hasAttachments = widget.viewModel.attachments.value.isNotEmpty;
    if (text.isEmpty && command == null && !hasAttachments) {
      return;
    }
    final queued = command == null
        ? await widget.viewModel.enqueuePrompt(
            text,
            executionOptions: _executionOptions.value,
          )
        : await widget.viewModel.enqueueCommand(
            command.name,
            text,
            executionOptions: _commandExecutionOptions(command),
          );
    if (queued) {
      _composerController.clear();
    }
  }

  Future<void> _pickAttachments() async {
    final result = await widget.viewModel.pickAttachments();
    if (!mounted || result is! AttachmentPickRejected) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _enterVoiceMode() async {
    final voiceViewModel = widget.voiceViewModel;
    if (voiceViewModel == null) return;
    _voiceDraftPrefix = _composerController.text;
    await voiceViewModel.enterModeFromUserAction();
  }

  Future<void> _startVoiceCapture() async {
    final voiceViewModel = widget.voiceViewModel;
    if (voiceViewModel == null) return;
    await voiceViewModel.startSegmentFromUserAction();
    if (voiceViewModel.state.value is VoiceRecording) {
      await HapticFeedback.mediumImpact();
    }
  }

  void _applyVoiceState() {
    final voiceViewModel = widget.voiceViewModel;
    if (!mounted || voiceViewModel == null) return;
    final state = voiceViewModel.state.value;
    final transcript = switch (state) {
      VoiceRecording(:final partialTranscript) => partialTranscript,
      VoiceTranscribing(:final partialTranscript) => partialTranscript,
      VoiceReady(:final transcript) => transcript,
      _ => null,
    };
    if (transcript != null) {
      final prefix = _voiceDraftPrefix ?? _composerController.text;
      final separator = prefix.trim().isEmpty || transcript.isEmpty ? '' : '\n';
      final text = '$prefix$separator$transcript';
      _composerController
        ..text = text
        ..selection = TextSelection.collapsed(offset: text.length);
    }
    if (state is VoiceIdle || state is VoiceUnavailable) {
      _voiceDraftPrefix = null;
    }
    setState(() {});
  }

  PromptExecutionOptions _commandExecutionOptions(
    OpenCodeSlashCommand command,
  ) {
    return PromptExecutionOptions(
      modelProviderId:
          command.model?.providerId ?? _executionOptions.value.modelProviderId,
      modelId: command.model?.modelId ?? _executionOptions.value.modelId,
      agentName: command.agentName ?? _executionOptions.value.agentName,
    );
  }

  Future<void> _selectCommand(List<OpenCodeSlashCommand> commands) async {
    final selectedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Slash command'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Message'),
                subtitle: const Text('Send a regular queued prompt'),
                onTap: () => Navigator.of(context).pop(''),
              ),
              for (final command in commands)
                ListTile(
                  title: Text('/${command.name}'),
                  subtitle: Text(command.description ?? 'Run slash command'),
                  selected: command.name == _selectedCommand?.name,
                  onTap: () => Navigator.of(context).pop(command.name),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selectedName == null) {
      return;
    }
    setState(
      () => _selectedCommand = selectedName.isEmpty
          ? null
          : commands.firstWhere((command) => command.name == selectedName),
    );
  }

  Future<void> _selectExecutionOptions(
    OpenCodeCapabilities capabilities,
  ) async {
    final selected = await showDialog<PromptExecutionOptions>(
      context: context,
      builder: (context) {
        var model = _selectedModel(capabilities.models);
        var agent = _selectedAgent(capabilities.agents);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Prompt execution'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<OpenCodeModel?>(
                    initialValue: model,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Model'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Default'),
                      ),
                      ...capabilities.models
                          .where((candidate) => candidate.isProviderConnected)
                          .map(
                            (candidate) => DropdownMenuItem(
                              value: candidate,
                              child: Text(
                                candidate.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                    ],
                    onChanged: (value) => setDialogState(() => model = value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<OpenCodeAgent?>(
                    initialValue: agent,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Agent'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Default'),
                      ),
                      ...capabilities.agents.map(
                        (candidate) => DropdownMenuItem(
                          value: candidate,
                          child: Text(candidate.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => agent = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  PromptExecutionOptions(
                    modelProviderId: model?.providerId,
                    modelId: model?.id,
                    agentName: agent?.name,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      _executionOptions.value = selected;
    }
  }

  OpenCodeModel? _selectedModel(List<OpenCodeModel> models) {
    for (final model in models) {
      if (model.providerId == _executionOptions.value.modelProviderId &&
          model.id == _executionOptions.value.modelId) {
        return model;
      }
    }
    return null;
  }

  OpenCodeAgent? _selectedAgent(List<OpenCodeAgent> agents) {
    for (final agent in agents) {
      if (agent.name == _executionOptions.value.agentName) {
        return agent;
      }
    }
    return null;
  }

  Future<void> _confirmSendNow(QueuedPrompt prompt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Abort current generation and send now?'),
          content: const Text(
            'This cancels whatever the session is currently generating, '
            'then sends this queued prompt immediately, ahead of the rest '
            'of the queue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Abort & send now'),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await widget.viewModel.sendNow(prompt.id);
    }
  }

  Future<void> _confirmRevert(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revert this message?'),
        content: const Text(
          'OpenCode will revert the session to this message. Later messages '
          'and session changes may be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revert message'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final failure = await widget.viewModel.revert(message.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure?.message ?? 'Message reverted')),
    );
  }

  void _updateJumpToLatestVisibility() {
    if (!_transcriptController.hasClients) {
      return;
    }
    // The transcript is reversed, so offset 0 is the newest message and no
    // scrolling is needed to stay anchored to it.
    final shouldShow = _transcriptController.position.pixels > 48;
    if (shouldShow != _showJumpToLatest && mounted) {
      setState(() => _showJumpToLatest = shouldShow);
    }
  }

  void _jumpToLatest() {
    if (_transcriptController.hasClients) {
      _transcriptController.jumpTo(0);
    }
  }

  Widget _buildTranscript(List<ChatMessage> messages) {
    return Stack(
      children: [
        Transcript(
          messages: messages,
          onRefresh: widget.viewModel.refreshFromUserAction,
          onRevert: _confirmRevert,
          controller: _transcriptController,
        ),
        // Reconciliation floats over the transcript so the previous messages
        // stay readable and the list is never rebuilt from an empty state.
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.viewModel.refreshing,
            builder: (context, refreshing, _) {
              if (!refreshing) {
                return const SizedBox.shrink();
              }
              return Center(
                child: Semantics(
                  liveRegion: true,
                  label: 'Syncing this conversation',
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Syncing…',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(right: 16, bottom: 16, child: _composerActionColumn()),
      ],
    );
  }

  Widget _composerActionColumn() {
    final capabilitiesViewModel = widget.capabilitiesViewModel;
    Widget buildActions(List<OpenCodeSlashCommand> commands) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showJumpToLatest) ...[
          FloatingActionButton.small(
            heroTag: 'scroll-to-latest',
            onPressed: _jumpToLatest,
            tooltip: 'Scroll to latest message',
            child: const Icon(Icons.south),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.voiceViewModel case final voiceViewModel?)
          ValueListenableBuilder<VoiceUiState>(
            valueListenable: voiceViewModel.state,
            builder: (context, state, _) => ValueListenableBuilder<bool>(
              valueListenable: voiceViewModel.hasSelectedModel,
              builder: (context, hasModel, _) {
                if (!hasModel || state is! VoiceIdle) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FloatingActionButton.small(
                    heroTag: 'start-voice-mode',
                    onPressed: _enterVoiceMode,
                    tooltip: 'Start voice mode',
                    child: const Icon(Icons.mic_rounded),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: EdgeInsets.only(bottom: commands.isEmpty ? 0 : 8),
          child: FloatingActionButton.small(
            heroTag: 'add-attachment',
            onPressed: _pickAttachments,
            tooltip: 'Add attachment',
            child: const Icon(Icons.attach_file_rounded),
          ),
        ),
        if (commands.isNotEmpty)
          FloatingActionButton.small(
            heroTag: 'choose-slash-command',
            onPressed: () => _selectCommand(commands),
            tooltip: 'Choose slash command',
            child: const Icon(Icons.code_rounded),
          ),
      ],
    );
    if (capabilitiesViewModel == null) {
      return buildActions(const []);
    }
    return ValueListenableBuilder<CapabilitiesUiState>(
      valueListenable: capabilitiesViewModel,
      builder: (context, state, _) => buildActions(
        state is CapabilitiesReady ? state.capabilities.commands : const [],
      ),
    );
  }

  Widget _artifactsPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _executionPanel(),
      const SizedBox(height: 8),
      ValueListenableBuilder<SessionArtifactsState>(
        valueListenable: widget.viewModel.artifacts,
        builder: (context, state, _) => SessionArtifactsPanel(
          state: state,
          onRefresh: widget.viewModel.reloadArtifacts,
        ),
      ),
    ],
  );

  Widget _executionPanel() {
    final capabilitiesViewModel = widget.capabilitiesViewModel;
    if (capabilitiesViewModel == null) {
      return const _ExecutionPanel(
        modelName: 'Unavailable',
        agentName: 'Unavailable',
      );
    }
    return ValueListenableBuilder<PromptExecutionOptions>(
      valueListenable: _executionOptions,
      builder: (context, options, _) =>
          ValueListenableBuilder<CapabilitiesUiState>(
            valueListenable: capabilitiesViewModel,
            builder: (context, state, _) {
              final capabilities = state is CapabilitiesReady
                  ? state.capabilities
                  : null;
              final selectedModel = capabilities == null
                  ? null
                  : _selectedModel(capabilities.models);
              final selectedAgent = capabilities == null
                  ? null
                  : _selectedAgent(capabilities.agents);
              final configuredModel = options.modelId;
              final modelName =
                  selectedModel?.name ??
                  (configuredModel == null
                      ? 'OpenCode default'
                      : '${options.modelProviderId}/$configuredModel');
              final agentName =
                  selectedAgent?.name ??
                  options.agentName ??
                  'OpenCode default';
              return _ExecutionPanel(
                modelName: modelName,
                agentName: agentName,
                loading:
                    state is CapabilitiesIdle || state is CapabilitiesLoading,
                failure: state is CapabilitiesError
                    ? state.failure.message
                    : null,
                onSelect: capabilities == null
                    ? null
                    : () => _selectExecutionOptions(capabilities),
                onRetry: state is CapabilitiesError
                    ? capabilitiesViewModel.retry
                    : null,
              );
            },
          ),
    );
  }

  Future<void> _showArtifacts() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (context, scrollController) =>
          ValueListenableBuilder<SessionArtifactsState>(
            valueListenable: widget.viewModel.artifacts,
            builder: (context, state, _) => ListView(
              controller: scrollController,
              children: [
                _executionPanel(),
                const SizedBox(height: 8),
                SessionArtifactsPanel(
                  state: state,
                  onRefresh: widget.viewModel.reloadArtifacts,
                ),
              ],
            ),
          ),
    ),
  );

  Widget _transcriptPanel() => ValueListenableBuilder<ConversationUiState>(
    valueListenable: widget.viewModel.messages,
    builder: (context, state, _) {
      return switch (state) {
        ConversationLoading() => Center(
          child: Semantics(
            label: 'Loading conversation',
            child: const CircularProgressIndicator(),
          ),
        ),
        ConversationError(:final failure) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(failure.message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.viewModel.reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        ConversationReady(:final messages) => _buildTranscript(messages),
      };
    },
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.session.title.isEmpty
                  ? 'Untitled session'
                  : widget.session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              directoryName(widget.session.directory),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showArtifacts,
            icon: const Icon(Icons.assignment_outlined),
            tooltip: 'Session artifacts',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<SseConnectionState>(
            valueListenable: widget.viewModel.connectionState,
            builder: (context, state, _) {
              final banner = _connectionBanner(state);
              if (banner == null) {
                return const SizedBox.shrink();
              }
              return ConnectionStatusBanner(
                banner,
                reconnecting:
                    state is SseReconnecting || state is SseReconciling,
                onRetry: state is SseDisconnected
                    ? widget.viewModel.retryConnection
                    : null,
              );
            },
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A context panel only becomes persistent once it can retain
                // a readable transcript width. Phones keep a one-column flow.
                if (constraints.maxWidth < 900) {
                  return _transcriptPanel();
                }
                return Row(
                  children: [
                    Expanded(child: _transcriptPanel()),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 320,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        child: _artifactsPanel(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ValueListenableBuilder<PendingApproval?>(
            valueListenable: widget.viewModel.pendingApproval,
            builder: (context, approval, _) {
              if (approval == null) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  const Divider(height: 1),
                  ApprovalDock(
                    key: ValueKey(_approvalKey(approval)),
                    approval: approval,
                    onRespondToPermission: widget.viewModel.respondToPermission,
                    onReplyToQuestion: widget.viewModel.replyToQuestion,
                    onRejectQuestion: widget.viewModel.rejectQuestion,
                  ),
                ],
              );
            },
          ),
          const Divider(height: 1),
          ValueListenableBuilder<List<QueuedPrompt>>(
            valueListenable: widget.viewModel.queue,
            builder: (context, prompts, _) {
              final activePrompts = prompts
                  .where(
                    (prompt) => prompt.state != QueuedPromptState.acknowledged,
                  )
                  .toList(growable: false);
              if (activePrompts.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                children: [
                  const Divider(height: 1),
                  QueuePanel(
                    prompts: activePrompts,
                    onRemove: (prompt) =>
                        widget.viewModel.removeFromQueue(prompt.id),
                    onSendNow: _confirmSendNow,
                    onMergeIntoPrevious: (prompt) =>
                        widget.viewModel.mergeIntoPrevious(prompt.id),
                  ),
                ],
              );
            },
          ),
          SafeArea(
            top: false,
            child: Composer(
              controller: _composerController,
              command: _selectedCommand,
              attachments: widget.viewModel.attachments,
              onRemoveAttachment: widget.viewModel.removeAttachment,
              onSubmit: _submitComposer,
              voiceState: widget.voiceViewModel?.state,
              onVoiceHoldStart: widget.voiceViewModel == null
                  ? null
                  : _startVoiceCapture,
              onVoiceHoldEnd:
                  widget.voiceViewModel?.finishSegmentFromUserAction,
              onVoiceStop: widget.voiceViewModel?.stopModeFromUserAction,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExecutionPanel extends StatelessWidget {
  const _ExecutionPanel({
    required this.modelName,
    required this.agentName,
    this.loading = false,
    this.failure,
    this.onSelect,
    this.onRetry,
  });

  final String modelName;
  final String agentName;
  final bool loading;
  final String? failure;
  final VoidCallback? onSelect;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Execution',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: const Text('Model'),
              subtitle: Text(modelName),
              trailing: loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : onSelect == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: onSelect,
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: const Text('Agent'),
              subtitle: Text(agentName),
              trailing: onSelect == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded),
              onTap: onSelect,
            ),
            if (failure case final failure?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: Text(failure)),
                    TextButton(
                      onPressed: onRetry == null
                          ? null
                          : () => unawaited(onRetry!()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
