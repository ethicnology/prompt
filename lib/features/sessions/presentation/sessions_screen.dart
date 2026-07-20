import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection/domain/server_profile.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import 'sessions_view_model.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    required this.profile,
    required this.viewModel,
    required this.onOpenSession,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final ValueChanged<OpenCodeSession> onOpenSession;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  @override
  void initState() {
    super.initState();
    widget.viewModel.load(widget.profile);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SessionsUiState>(
      valueListenable: widget.viewModel,
      builder: (context, state, _) {
        return switch (state) {
          SessionsIdle() || SessionsLoading() => Center(
            child: Semantics(
              label: 'Loading sessions',
              child: CircularProgressIndicator(),
            ),
          ),
          SessionsEmpty() => _EmptySessions(
            onRefresh: () => widget.viewModel.load(widget.profile),
          ),
          SessionsError(:final failure) => _SessionsError(
            failure: failure,
            onRetry: () => widget.viewModel.load(widget.profile),
          ),
          SessionsReady(:final sessions) => _PrimarySessionsList(
            sessions: sessions,
            onRefresh: () => widget.viewModel.load(widget.profile),
            onOpenSession: widget.onOpenSession,
            onSessionLongPress: _showSessionActions,
          ),
        };
      },
    );
  }

  Future<void> _showSessionActions(OpenCodeSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('Copy session ID'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: session.id));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Session ID copied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename session'),
              onTap: () {
                Navigator.of(context).pop();
                _renameSession(session);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete session',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _deleteSession(session);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameSession(OpenCodeSession session) async {
    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || title == null || title.isEmpty || title == session.title) {
      return;
    }
    final failure = await widget.viewModel.rename(
      widget.profile,
      session,
      title,
    );
    if (mounted && failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _deleteSession(OpenCodeSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'Delete "${session.title}" from OpenCode? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    final failure = await widget.viewModel.delete(widget.profile, session);
    if (mounted && failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _PrimarySessionsList extends StatelessWidget {
  const _PrimarySessionsList({
    required this.sessions,
    required this.onRefresh,
    required this.onOpenSession,
    required this.onSessionLongPress,
  });

  final List<OpenCodeSession> sessions;
  final Future<void> Function() onRefresh;
  final ValueChanged<OpenCodeSession> onOpenSession;
  final ValueChanged<OpenCodeSession> onSessionLongPress;

  @override
  Widget build(BuildContext context) {
    final primary = sessions
        .where(
          (session) => session.parentId == null || session.parentId!.isEmpty,
        )
        .toList(growable: false);
    final subagents = sessions
        .where(
          (session) => session.parentId != null && session.parentId!.isNotEmpty,
        )
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (subagents.isNotEmpty)
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: TextButton.icon(
                    onPressed: () => _showSubagents(context, subagents),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: Text('${subagents.length} subagents'),
                  ),
                ),
              ),
            ),
          SliverList.builder(
            itemCount: primary.length,
            itemBuilder: (context, index) {
              final session = primary[index];
              return _SessionTile(
                session: session,
                onTap: () => onOpenSession(session),
                onLongPress: () => onSessionLongPress(session),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showSubagents(BuildContext context, List<OpenCodeSession> subagents) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.builder(
          itemCount: subagents.length,
          itemBuilder: (context, index) {
            final session = subagents[index];
            return _SessionTile(
              session: session,
              onTap: () {
                Navigator.of(context).pop();
                onOpenSession(session);
              },
              onLongPress: () => onSessionLongPress(session),
            );
          },
        ),
      ),
    );
  }
}

class _EmptySessions extends StatelessWidget {
  const _EmptySessions({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No sessions yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Start a conversation in OpenCode, then pull down to refresh.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsError extends StatelessWidget {
  const _SessionsError({required this.failure, required this.onRetry});

  final SessionsFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_problem, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.onTap,
    required this.onLongPress,
  });

  final OpenCodeSession session;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectName = _directoryName(session.directory);
    final changeSummary = _changeSummary(session);

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        session.parentId == null ? Icons.forum_outlined : Icons.call_split,
      ),
      title: Text(
        session.title.isEmpty ? 'Untitled session' : session.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          projectName,
          _relativeTime(session.updatedAt),
          changeSummary,
        ].whereType<String>().join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right, color: theme.colorScheme.outline),
    );
  }

  String _directoryName(String directory) {
    final normalized = directory.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    return segments.isEmpty ? directory : segments.last;
  }

  String? _changeSummary(OpenCodeSession session) {
    final files = session.changedFiles;
    if (files == null) {
      return null;
    }
    final additions = session.additions ?? 0;
    final deletions = session.deletions ?? 0;
    return '$files files  +$additions  -$deletions';
  }

  String _relativeTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) {
      return 'Just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    }
    return '${difference.inDays}d ago';
  }
}
