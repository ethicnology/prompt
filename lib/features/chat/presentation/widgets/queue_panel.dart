import 'package:flutter/material.dart';

import '../../../queue/queue.dart';

/// Lists the prompts and commands waiting to be dispatched for the session.
class QueuePanel extends StatelessWidget {
  const QueuePanel({
    required this.prompts,
    required this.onRemove,
    required this.onSendNow,
    super.key,
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
          prompt.operationType == QueuedOperationType.command
              ? '/${prompt.commandName}${prompt.promptText.isEmpty ? '' : ' ${prompt.promptText}'}'
              : prompt.promptText,
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
