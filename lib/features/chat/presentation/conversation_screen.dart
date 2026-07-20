import 'package:flutter/material.dart';

import '../../connection/domain/server_profile.dart';
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
  @override
  void initState() {
    super.initState();
    widget.viewModel.load(widget.profile, widget.session);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.session.title)),
      body: ValueListenableBuilder<ConversationUiState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) {
          return switch (state) {
            ConversationLoading() => Center(
              child: Semantics(
                label: 'Loading conversation',
                child: CircularProgressIndicator(),
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
                      onPressed: () {
                        widget.viewModel.load(widget.profile, widget.session);
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
            ConversationReady(:final messages) => RefreshIndicator(
              onRefresh: () =>
                  widget.viewModel.load(widget.profile, widget.session),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList.separated(
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return _MessageBubble(message: messages[index]);
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                    ),
                  ),
                ],
              ),
            ),
          };
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

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
