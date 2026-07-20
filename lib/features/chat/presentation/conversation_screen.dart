import 'dart:async';

import 'package:flutter/material.dart';

import '../../connection/domain/server_profile.dart';
import '../../queue/queue.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import '../domain/pending_approval.dart';
import '../domain/permission_response.dart';
import 'conversation_view_model.dart';

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

/// A stable identity for [approval], used as `_ApprovalDock`'s key so a
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
    super.key,
  });

  final ServerProfile profile;
  final OpenCodeSession session;
  final ConversationViewModel viewModel;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composerController = TextEditingController();
  StreamSubscription<String>? _queueErrorSubscription;

  @override
  void initState() {
    super.initState();
    widget.viewModel.open(widget.profile, widget.session);
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
    _composerController.dispose();
    widget.viewModel.leave();
    super.dispose();
  }

  Future<void> _submitComposer() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _composerController.clear();
    await widget.viewModel.enqueuePrompt(text);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session.title)),
      body: Column(
        children: [
          ValueListenableBuilder<SseConnectionState>(
            valueListenable: widget.viewModel.connectionState,
            builder: (context, state, _) {
              final banner = _connectionBanner(state);
              if (banner == null) {
                return const SizedBox.shrink();
              }
              return _ConnectionStatusBanner(banner);
            },
          ),
          Expanded(
            child: ValueListenableBuilder<ConversationUiState>(
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
                  ConversationReady(:final messages) => _Transcript(
                    messages: messages,
                    onRefresh: widget.viewModel.reload,
                  ),
                };
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
                  _ApprovalDock(
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
                  _QueuePanel(
                    prompts: activePrompts,
                    onRemove: (prompt) =>
                        widget.viewModel.removeFromQueue(prompt.id),
                    onSendNow: _confirmSendNow,
                  ),
                ],
              );
            },
          ),
          _Composer(controller: _composerController, onSubmit: _submitComposer),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.messages, required this.onRefresh});

  final List<ChatMessage> messages;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final visibleMessages = messages
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.separated(
              itemCount: visibleMessages.length,
              itemBuilder: (context, index) {
                final message = visibleMessages[index];
                return _MessageBubble(
                  key: ValueKey(message.id),
                  message: message,
                );
              },
              separatorBuilder: (_, _) => const SizedBox(height: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.prompts,
    required this.onRemove,
    required this.onSendNow,
  });

  final List<QueuedPrompt> prompts;
  final ValueChanged<QueuedPrompt> onRemove;
  final ValueChanged<QueuedPrompt> onSendNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  'Queue: ${prompts.length} '
                  '${prompts.length == 1 ? 'prompt' : 'prompts'}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: prompts.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final prompt = prompts[index];
                  return _QueueRow(
                    prompt: prompt,
                    position: index + 1,
                    onRemove: () => onRemove(prompt),
                    onSendNow: () => onSendNow(prompt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.prompt,
    required this.position,
    required this.onRemove,
    required this.onSendNow,
  });

  final QueuedPrompt prompt;
  final int position;
  final VoidCallback onRemove;
  final VoidCallback onSendNow;

  @override
  Widget build(BuildContext context) {
    final canSendNow = prompt.state == QueuedPromptState.queued;
    final canRemove = prompt.state != QueuedPromptState.sending;
    final statusLabel = _statusLabel(prompt);

    return Semantics(
      label: 'Queued prompt $position, $statusLabel',
      child: ListTile(
        dense: true,
        leading: Text('$position'),
        title: Text(
          prompt.promptText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(statusLabel),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (canSendNow)
              IconButton(
                onPressed: onSendNow,
                icon: const Icon(Icons.bolt),
                tooltip: 'Send now (aborts current generation)',
              ),
            IconButton(
              onPressed: canRemove ? onRemove : null,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove from queue',
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(QueuedPrompt prompt) {
    return switch (prompt.state) {
      QueuedPromptState.queued => 'Queued',
      QueuedPromptState.sending => 'Sending…',
      QueuedPromptState.acknowledged => 'Sent',
      QueuedPromptState.failed => 'Failed to send',
      QueuedPromptState.paused => switch (prompt.pauseReason) {
        QueuePauseReason.submissionUnknown =>
          'Paused: delivery unconfirmed. Review the conversation, then '
              'resume or remove.',
        QueuePauseReason.permissionPending => 'Paused: awaiting permission',
        QueuePauseReason.questionPending => 'Paused: awaiting a question',
        QueuePauseReason.sessionGenerating => 'Paused: session busy',
        QueuePauseReason.networkUnavailable => 'Paused: network unavailable',
        QueuePauseReason.sessionDeleted => 'Paused: session deleted',
        QueuePauseReason.serverRejected => 'Paused: server rejected it',
        null => 'Paused',
      },
    };
  }
}

/// A non-dismissible dock shown above the composer whenever
/// [ConversationViewModel.pendingApproval] is not `null`: a pending
/// tool-call permission, or a pending question request. There is
/// deliberately no close/dismiss affordance — the human must allow,
/// always-allow, deny, or answer/reject before this goes away, and it
/// disappears on its own the moment that submission succeeds (see
/// [ConversationViewModel.respondToPermission]/[replyToQuestion]/
/// [rejectQuestion]).
///
/// [approval] and every [QuestionPrompt] it may carry can describe a
/// sensitive command, path, or question; this widget renders that detail
/// only to the person being asked to decide it and never logs or persists
/// it (see `pending_approval.dart`).
class _ApprovalDock extends StatefulWidget {
  const _ApprovalDock({
    required this.approval,
    required this.onRespondToPermission,
    required this.onReplyToQuestion,
    required this.onRejectQuestion,
    super.key,
  });

  final PendingApproval approval;
  final Future<void> Function(String permissionId, PermissionResponse response)
  onRespondToPermission;
  final Future<void> Function(String requestId, List<List<String>> answers)
  onReplyToQuestion;
  final Future<void> Function(String requestId) onRejectQuestion;

  @override
  State<_ApprovalDock> createState() => _ApprovalDockState();
}

class _ApprovalDockState extends State<_ApprovalDock> {
  bool _submitting = false;
  final Map<int, Set<String>> _selectedOptions = <int, Set<String>>{};
  final Map<int, TextEditingController> _customControllers =
      <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _initQuestionControllers();
  }

  @override
  void dispose() {
    for (final controller in _customControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initQuestionControllers() {
    final approval = widget.approval;
    if (approval is! PendingQuestionApproval) {
      return;
    }
    for (var i = 0; i < approval.questions.length; i++) {
      _selectedOptions[i] = <String>{};
      final controller = TextEditingController();
      // Submit's enabled state depends on whether any question still has
      // no answer; a custom-answer keystroke must rebuild this dock, not
      // just the `TextField` itself.
      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      _customControllers[i] = controller;
    }
  }

  @override
  Widget build(BuildContext context) {
    final approval = widget.approval;
    return Semantics(
      liveRegion: true,
      container: true,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (approval) {
            PendingPermissionApproval() => _buildPermission(context, approval),
            PendingQuestionApproval() => _buildQuestions(context, approval),
          },
        ),
      ),
    );
  }

  Widget _buildPermission(
    BuildContext context,
    PendingPermissionApproval approval,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Approval needed: ${approval.toolType}',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(approval.title),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _submitting
                  ? null
                  : () => _respondToPermission(
                      approval.permissionId,
                      PermissionResponse.once,
                    ),
              child: const Text('Allow once'),
            ),
            OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => _respondToPermission(
                      approval.permissionId,
                      PermissionResponse.always,
                    ),
              child: const Text('Always allow'),
            ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => _respondToPermission(
                      approval.permissionId,
                      PermissionResponse.reject,
                    ),
              child: const Text('Deny'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _respondToPermission(
    String permissionId,
    PermissionResponse response,
  ) async {
    setState(() => _submitting = true);
    await widget.onRespondToPermission(permissionId, response);
  }

  Widget _buildQuestions(
    BuildContext context,
    PendingQuestionApproval approval,
  ) {
    final theme = Theme.of(context);
    final canSubmit = !_submitting && _everyQuestionAnswered(approval);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'The agent is asking a question',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < approval.questions.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == approval.questions.length - 1 ? 12 : 16,
            ),
            child: _QuestionCard(
              prompt: approval.questions[i],
              selected: _selectedOptions[i]!,
              customController: _customControllers[i]!,
              onToggleOption: (label) =>
                  _toggleOption(i, label, approval.questions[i].multiple),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: canSubmit ? () => _submitAnswers(approval) : null,
              child: const Text('Submit answers'),
            ),
            TextButton(
              onPressed: _submitting ? null : () => _reject(approval.requestId),
              child: const Text('Reject'),
            ),
          ],
        ),
      ],
    );
  }

  bool _everyQuestionAnswered(PendingQuestionApproval approval) {
    for (var i = 0; i < approval.questions.length; i++) {
      final hasSelection = (_selectedOptions[i] ?? const <String>{}).isNotEmpty;
      final hasCustom =
          (_customControllers[i]?.text.trim().isNotEmpty) ?? false;
      if (!hasSelection && !hasCustom) {
        return false;
      }
    }
    return true;
  }

  void _toggleOption(int index, String label, bool multiple) {
    setState(() {
      final current = _selectedOptions[index]!;
      if (multiple) {
        if (!current.add(label)) {
          current.remove(label);
        }
      } else {
        current
          ..clear()
          ..add(label);
      }
    });
  }

  Future<void> _submitAnswers(PendingQuestionApproval approval) async {
    final answers = <List<String>>[];
    for (var i = 0; i < approval.questions.length; i++) {
      final answer = <String>[...?_selectedOptions[i]];
      final custom = _customControllers[i]?.text.trim() ?? '';
      if (custom.isNotEmpty) {
        answer.add(custom);
      }
      answers.add(answer);
    }
    setState(() => _submitting = true);
    await widget.onReplyToQuestion(approval.requestId, answers);
  }

  Future<void> _reject(String requestId) async {
    setState(() => _submitting = true);
    await widget.onRejectQuestion(requestId);
  }
}

/// One question within an [_ApprovalDock] showing [PendingQuestionApproval.
/// questions]. Options render as accessible, keyboard/touch-operable
/// [FilterChip]s; a free-text answer is offered alongside them whenever
/// [QuestionPrompt.allowsCustomAnswer] is true.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.prompt,
    required this.selected,
    required this.customController,
    required this.onToggleOption,
  });

  final QuestionPrompt prompt;
  final Set<String> selected;
  final TextEditingController customController;
  final ValueChanged<String> onToggleOption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prompt.header, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(prompt.question),
          if (prompt.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in prompt.options)
                  Semantics(
                    label: '${option.label}: ${option.description}',
                    selected: selected.contains(option.label),
                    button: true,
                    child: FilterChip(
                      label: Text(option.label),
                      selected: selected.contains(option.label),
                      onSelected: (_) => onToggleOption(option.label),
                    ),
                  ),
              ],
            ),
          ],
          if (prompt.allowsCustomAnswer) ...[
            const SizedBox(height: 8),
            Semantics(
              label: 'Custom answer for ${prompt.header}',
              child: TextField(
                controller: customController,
                decoration: const InputDecoration(
                  hintText: 'Or type your own answer',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              label: 'Prompt composer',
              hint: 'Enter a prompt; it joins the send queue',
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message this session…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: () {
              unawaited(onSubmit());
            },
            icon: const Icon(Icons.send),
            tooltip: 'Queue this prompt',
          ),
        ],
      ),
    );
  }
}

/// A slim, non-dismissible banner announcing [text] above the transcript.
/// `liveRegion: true` makes a screen reader announce a status change (for
/// example connected -> reconnecting) without the user having to find and
/// re-read the banner themselves, matching this app's rule that
/// connection state must not rely on color or animation alone.
class _ConnectionStatusBanner extends StatelessWidget {
  const _ConnectionStatusBanner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final userMessage = message.role == ChatMessageRole.user;
    final theme = Theme.of(context);
    final background = userMessage
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: userMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              message.text,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}
