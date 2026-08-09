import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/prompt_theme.dart';
import '../../domain/chat_message.dart';
import '../basic_markdown_text.dart';

class Transcript extends StatefulWidget {
  const Transcript({
    required this.messages,
    required this.onRefresh,
    required this.controller,
    required this.onRevert,
    super.key,
  });

  final List<ChatMessage> messages;
  final Future<void> Function() onRefresh;
  final ScrollController controller;
  final ValueChanged<ChatMessage> onRevert;

  @override
  State<Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<Transcript> {
  static const _refreshThreshold = 72.0;
  double _bottomOverscroll = 0;
  bool _refreshing = false;

  bool _handleScroll(ScrollNotification notification) {
    if (_refreshing) return false;
    if (notification is OverscrollNotification &&
        notification.metrics.extentAfter == 0 &&
        notification.overscroll > 0) {
      setState(() {
        _bottomOverscroll = (_bottomOverscroll + notification.overscroll).clamp(
          0,
          _refreshThreshold,
        );
      });
      return false;
    }
    if (notification is ScrollEndNotification && _bottomOverscroll > 0) {
      final shouldRefresh = _bottomOverscroll >= _refreshThreshold;
      setState(() => _bottomOverscroll = 0);
      if (shouldRefresh) {
        setState(() => _refreshing = true);
        widget.onRefresh().whenComplete(() {
          if (mounted) setState(() => _refreshing = false);
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = widget.messages
        .where(
          (message) =>
              message.text.trim().isNotEmpty || message.details.isNotEmpty,
        )
        .toList(growable: false);

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScroll,
      child: Stack(
        children: [
          CustomScrollView(
            controller: widget.controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                sliver: SliverList.separated(
                  itemCount: visibleMessages.length,
                  itemBuilder: (context, index) {
                    final message = visibleMessages[index];
                    return _MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                      onRevert: () => widget.onRevert(message),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: IgnorePointer(
              child: Center(
                child: _refreshing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _bottomOverscroll > 0
                    ? Text(
                        _bottomOverscroll >= _refreshThreshold
                            ? 'Release to refresh'
                            : 'Pull up to refresh',
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onRevert,
    super.key,
  });

  final ChatMessage message;
  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final userMessage = message.role == ChatMessageRole.user;
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    final background = userMessage
        ? theme.colorScheme.primaryContainer
        : Colors.transparent;

    return Align(
      alignment: userMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(userMessage ? 18 : 0),
            border: userMessage
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.28),
                  )
                : null,
          ),
          child: Padding(
            padding: EdgeInsets.all(userMessage ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      userMessage
                          ? Icons.person_outline_rounded
                          : Icons.auto_awesome_outlined,
                      size: 15,
                      color: userMessage
                          ? theme.colorScheme.primary
                          : tokens.subtle,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      userMessage ? 'You' : 'OpenCode',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: userMessage
                            ? theme.colorScheme.primary
                            : tokens.subtle,
                      ),
                    ),
                    const Spacer(),
                    if (message.text.trim().isNotEmpty)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Message copied')),
                          );
                        },
                        icon: const Icon(Icons.content_copy_outlined, size: 17),
                        tooltip: 'Copy message',
                      ),
                  ],
                ),
                if (message.details.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final detail in message.details)
                    _MessageDetailCard(detail: detail),
                ],
                if (message.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  BasicMarkdownText(
                    text: message.text,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
                // Revert restores the session to just before a prompt, so it
                // only makes sense on the user message that started the turn.
                if (userMessage && message.id.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      message: 'Revert to this message',
                      child: TextButton.icon(
                        onPressed: onRevert,
                        icon: const Icon(Icons.undo_rounded, size: 17),
                        label: const Text('Revert'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageDetailCard extends StatelessWidget {
  const _MessageDetailCard({required this.detail});

  final ChatMessageDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    return switch (detail) {
      ChatReasoningDetail(:final text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          collapsedBackgroundColor: tokens.panelRaised,
          backgroundColor: tokens.panelRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: const Icon(Icons.psychology_outlined, size: 18),
          title: const Text('Reasoning'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(text, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
      ChatToolDetail() => _ToolDetailCard(detail: detail as ChatToolDetail),
    };
  }
}

class _ToolDetailCard extends StatelessWidget {
  const _ToolDetailCard({required this.detail});

  final ChatToolDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = _tokens(theme);
    final status = _toolStatus(detail.status);
    final isTask = detail.tool == 'task';
    final title = isTask ? 'Subagent task' : _toolLabel(detail.tool);
    final body = [
      detail.output,
      detail.error,
    ].whereType<String>().where((value) => value.isNotEmpty).join('\n\n');

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        collapsedBackgroundColor: tokens.panelRaised,
        backgroundColor: tokens.panelRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        leading: Icon(status.icon, size: 18, color: status.color(tokens)),
        title: Text(title),
        subtitle: Text(
          [
            status.label,
            detail.input,
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          if (body.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            )
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}

({IconData icon, String label, Color Function(PromptTokens) color}) _toolStatus(
  String status,
) => switch (status) {
  'pending' => (
    icon: Icons.hourglass_top_rounded,
    label: 'Queued',
    color: (tokens) => tokens.warning,
  ),
  'running' => (
    icon: Icons.sync_rounded,
    label: 'Running',
    color: (tokens) => tokens.warning,
  ),
  'completed' => (
    icon: Icons.check_circle_outline_rounded,
    label: 'Completed',
    color: (tokens) => tokens.success,
  ),
  _ => (
    icon: Icons.error_outline_rounded,
    label: 'Failed',
    color: (tokens) => tokens.danger,
  ),
};

String _toolLabel(String tool) => tool
    .split(RegExp('[-_]'))
    .where((segment) => segment.isNotEmpty)
    .map((segment) => '${segment[0].toUpperCase()}${segment.substring(1)}')
    .join(' ');

PromptTokens _tokens(ThemeData theme) =>
    theme.extension<PromptTokens>() ??
    const PromptTokens(
      panel: Color(0xfff5f7f6),
      panelRaised: Color(0xffecefed),
      subtle: Color(0xff59676c),
      success: Color(0xff13795b),
      warning: Color(0xff9a5600),
      danger: Color(0xffb42318),
      diffAdd: Color(0xffdcf8e9),
      diffDelete: Color(0xffffe5e4),
    );
