import 'package:flutter/material.dart';

import '../../connection/domain/server_profile.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import 'sessions_view_model.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    required this.profile,
    required this.viewModel,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;

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
          SessionsReady(:final sessions) => RefreshIndicator(
            onRefresh: () => widget.viewModel.load(widget.profile),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverList.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionTile(session: session);
                  },
                ),
              ],
            ),
          ),
        };
      },
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
  const _SessionTile({required this.session});

  final OpenCodeSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projectName = _directoryName(session.directory);
    final changeSummary = _changeSummary(session);

    return ListTile(
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
