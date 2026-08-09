import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection/domain/server_profile.dart';
import '../../capabilities/capabilities.dart';
import '../../queue/queue.dart';
import '../../sessions/domain/open_code_session.dart';
import '../../sessions/domain/session_load_result.dart';
import '../../voice/voice.dart';
import '../../../core/async/result.dart';
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
  bool _showJumpToLatest = false;
  bool _followingLatest = true;
  bool _scrollToLatestScheduled = false;
  PromptExecutionOptions _executionOptions = const PromptExecutionOptions();
  OpenCodeSlashCommand? _selectedCommand;
  late bool _isShared;
  bool _releasedForFork = false;
  String? _voiceDraftPrefix;

  @override
  void initState() {
    super.initState();
    _isShared = widget.session.shareUrl != null;
    _transcriptController.addListener(_updateJumpToLatestVisibility);
    widget.viewModel.open(widget.profile, widget.session);
    widget.capabilitiesViewModel?.load(widget.profile);
    widget.voiceViewModel?.state.addListener(_applyVoiceState);
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
    widget.voiceViewModel?.state.removeListener(_applyVoiceState);
    unawaited(widget.voiceViewModel?.cancel());
    _composerController.dispose();
    _transcriptController
      ..removeListener(_updateJumpToLatestVisibility)
      ..dispose();
    if (!_releasedForFork) {
      widget.viewModel.leave();
    }
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
            executionOptions: _executionOptions,
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

  Future<void> _toggleVoiceInput() async {
    final voiceViewModel = widget.voiceViewModel;
    if (voiceViewModel == null) return;
    if (voiceViewModel.state.value is VoiceRecording) {
      await voiceViewModel.stopFromUserAction();
      return;
    }
    _voiceDraftPrefix = _composerController.text;
    await voiceViewModel.startFromUserAction();
  }

  void _applyVoiceState() {
    final voiceViewModel = widget.voiceViewModel;
    if (!mounted || voiceViewModel == null) return;
    final state = voiceViewModel.state.value;
    final transcript = switch (state) {
      VoiceRecording(:final partialTranscript) => partialTranscript,
      VoiceTranscriptReady(:final transcript) => transcript,
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
    if (state is VoiceTranscriptReady || state is VoiceUnavailable) {
      _voiceDraftPrefix = null;
    }
    setState(() {});
  }

  PromptExecutionOptions _commandExecutionOptions(
    OpenCodeSlashCommand command,
  ) {
    return PromptExecutionOptions(
      modelProviderId:
          command.model?.providerId ?? _executionOptions.modelProviderId,
      modelId: command.model?.modelId ?? _executionOptions.modelId,
      agentName: command.agentName ?? _executionOptions.agentName,
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<OpenCodeModel?>(
                  initialValue: model,
                  decoration: const InputDecoration(labelText: 'Model'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Default')),
                    ...capabilities.models
                        .where((candidate) => candidate.isProviderConnected)
                        .map(
                          (candidate) => DropdownMenuItem(
                            value: candidate,
                            child: Text(candidate.name),
                          ),
                        ),
                  ],
                  onChanged: (value) => setDialogState(() => model = value),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<OpenCodeAgent?>(
                  initialValue: agent,
                  decoration: const InputDecoration(labelText: 'Agent'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Default')),
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
      setState(() => _executionOptions = selected);
    }
  }

  OpenCodeModel? _selectedModel(List<OpenCodeModel> models) {
    for (final model in models) {
      if (model.providerId == _executionOptions.modelProviderId &&
          model.id == _executionOptions.modelId) {
        return model;
      }
    }
    return null;
  }

  OpenCodeAgent? _selectedAgent(List<OpenCodeAgent> agents) {
    for (final agent in agents) {
      if (agent.name == _executionOptions.agentName) {
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

  Future<void> _fork() async {
    final result = await widget.viewModel.fork();
    if (!mounted || result == null) {
      return;
    }
    switch (result) {
      case Ok<OpenCodeSession, SessionsFailure>(:final value):
        final onOpenFork = widget.onOpenFork;
        if (onOpenFork == null) {
          await widget.viewModel.leave();
          if (mounted) Navigator.of(context).pop();
          return;
        }
        await widget.viewModel.leave();
        if (mounted) {
          _releasedForFork = true;
          onOpenFork(value);
        }
      case Err<OpenCodeSession, SessionsFailure>(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _share() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share this session?'),
        content: const Text(
          'OpenCode may upload the complete session to its sharing service. '
          'Anyone with the resulting link may be able to read it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Share session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await widget.viewModel.share();
    if (!mounted || result == null) return;
    switch (result) {
      case Ok<String?, SessionsFailure>(:final value):
        setState(() => _isShared = true);
        if (value != null) {
          await _showShareLink(value);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Session shared')));
        }
      case Err<String?, SessionsFailure>(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _showShareLink(String url) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Session share link'),
      content: SelectableText(url),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              this.context,
            ).showSnackBar(const SnackBar(content: Text('Share link copied')));
          },
          icon: const Icon(Icons.content_copy_outlined),
          label: const Text('Copy link'),
        ),
      ],
    ),
  );

  Future<void> _unshare() async {
    final failure = await widget.viewModel.unshare();
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    setState(() => _isShared = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session is no longer shared')),
    );
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
    final position = _transcriptController.position;
    final shouldShow = position.maxScrollExtent - position.pixels > 48;
    _followingLatest = !shouldShow;
    if (shouldShow != _showJumpToLatest && mounted) {
      setState(() => _showJumpToLatest = shouldShow);
    }
  }

  void _scheduleScrollToLatestIfFollowing() {
    if (!_followingLatest || _scrollToLatestScheduled) {
      return;
    }
    _scrollToLatestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToLatestScheduled = false;
      if (!mounted || !_transcriptController.hasClients) {
        return;
      }
      _transcriptController.jumpTo(
        _transcriptController.position.maxScrollExtent,
      );
    });
  }

  void _jumpToLatest() {
    setState(() {
      _followingLatest = true;
      _showJumpToLatest = false;
    });
    _scheduleScrollToLatestIfFollowing();
  }

  Widget _buildTranscript(List<ChatMessage> messages) {
    _scheduleScrollToLatestIfFollowing();
    return Stack(
      children: [
        Transcript(
          messages: messages,
          onRefresh: widget.viewModel.refreshFromUserAction,
          onRevert: _confirmRevert,
          controller: _transcriptController,
        ),
        if (_showJumpToLatest)
          Positioned(
            right: 20,
            bottom: 20,
            child: Semantics(
              button: true,
              label: 'Scroll to latest message',
              child: FloatingActionButton.small(
                heroTag: 'scroll-to-latest',
                onPressed: _jumpToLatest,
                tooltip: 'Scroll to latest message',
                child: const Icon(Icons.south),
              ),
            ),
          ),
      ],
    );
  }

  Widget _artifactsPanel() => ValueListenableBuilder<SessionArtifactsState>(
    valueListenable: widget.viewModel.artifacts,
    builder: (context, state, _) => SessionArtifactsPanel(
      state: state,
      onRefresh: widget.viewModel.reloadArtifacts,
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
          if (widget.capabilitiesViewModel case final capabilitiesViewModel?)
            ValueListenableBuilder<CapabilitiesUiState>(
              valueListenable: capabilitiesViewModel,
              builder: (context, state, _) {
                if (state is! CapabilitiesReady) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  onPressed: () => _selectExecutionOptions(state.capabilities),
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Choose model and agent',
                );
              },
            ),
          PopupMenuButton<_SessionAction>(
            tooltip: 'Session actions',
            onSelected: (action) => switch (action) {
              _SessionAction.fork => _fork(),
              _SessionAction.share => _share(),
              _SessionAction.unshare => _unshare(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _SessionAction.fork,
                child: Text('Fork session'),
              ),
              PopupMenuItem(
                value: _isShared
                    ? _SessionAction.unshare
                    : _SessionAction.share,
                child: Text(_isShared ? 'Unshare session' : 'Share session'),
              ),
            ],
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
                  return Column(
                    children: [
                      _artifactsPanel(),
                      Expanded(child: _transcriptPanel()),
                    ],
                  );
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
                  ),
                ],
              );
            },
          ),
          SafeArea(
            top: false,
            child: widget.capabilitiesViewModel == null
                ? Composer(
                    controller: _composerController,
                    command: _selectedCommand,
                    commands: const [],
                    attachments: widget.viewModel.attachments,
                    onPickAttachments: _pickAttachments,
                    onRemoveAttachment: widget.viewModel.removeAttachment,
                    onSelectCommand: _selectCommand,
                    onSubmit: _submitComposer,
                    voiceState: widget.voiceViewModel?.state,
                    hasSelectedVoiceModel:
                        widget.voiceViewModel?.hasSelectedModel,
                    onVoicePressed: _toggleVoiceInput,
                  )
                : ValueListenableBuilder<CapabilitiesUiState>(
                    valueListenable: widget.capabilitiesViewModel!,
                    builder: (context, capabilitiesState, _) {
                      final capabilities =
                          capabilitiesState is CapabilitiesReady
                          ? capabilitiesState.capabilities
                          : null;
                      final model = capabilities == null
                          ? null
                          : _selectedModel(capabilities.models);
                      final agent = capabilities == null
                          ? null
                          : _selectedAgent(capabilities.agents);
                      final executionLabel = capabilities == null
                          ? null
                          : '${model?.name ?? 'Default model'} · '
                                '${agent?.name ?? 'Default agent'}';
                      return Composer(
                        controller: _composerController,
                        command: _selectedCommand,
                        commands: capabilities?.commands ?? const [],
                        attachments: widget.viewModel.attachments,
                        onPickAttachments: _pickAttachments,
                        onRemoveAttachment: widget.viewModel.removeAttachment,
                        onSelectCommand: _selectCommand,
                        onSubmit: _submitComposer,
                        voiceState: widget.voiceViewModel?.state,
                        hasSelectedVoiceModel:
                            widget.voiceViewModel?.hasSelectedModel,
                        onVoicePressed: _toggleVoiceInput,
                        executionLabel: executionLabel,
                        onSelectExecution: capabilities == null
                            ? null
                            : () => _selectExecutionOptions(capabilities),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _SessionAction { fork, share, unshare }
