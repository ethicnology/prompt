import 'dart:async';

import 'package:flutter/material.dart';

import '../../connection/domain/server_profile.dart';
import '../../queue/queue.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/chat_load_result.dart';
import '../domain/chat_message.dart';
import 'conversation_view_model.dart';

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
                  ConversationReady(:final messages) => RefreshIndicator(
                    onRefresh: widget.viewModel.reload,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverList.separated(
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              return _MessageBubble(
                                key: ValueKey(message.id),
                                message: message,
                              );
                            },
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                };
              },
            ),
          ),
          const Divider(height: 1),
          ValueListenableBuilder<List<QueuedPrompt>>(
            valueListenable: widget.viewModel.queue,
            builder: (context, prompts, _) {
              return _QueuePanel(
                prompts: prompts,
                onRemove: (prompt) =>
                    widget.viewModel.removeFromQueue(prompt.id),
                onSendNow: _confirmSendNow,
              );
            },
          ),
          const Divider(height: 1),
          _Composer(controller: _composerController, onSubmit: _submitComposer),
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
                  prompts.isEmpty
                      ? 'Queue: empty'
                      : 'Queue: ${prompts.length} '
                            '${prompts.length == 1 ? 'prompt' : 'prompts'}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ),
            if (prompts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Prompts you send join this queue and are delivered once '
                  'the session is free.',
                ),
              )
            else
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
              message.text.isEmpty ? 'No text output.' : message.text,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}
