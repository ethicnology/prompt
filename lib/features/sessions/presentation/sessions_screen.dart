import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/async/result.dart';
import '../../connection/connection.dart';
import '../domain/open_code_project.dart';
import '../domain/open_code_session.dart';
import '../domain/session_load_result.dart';
import 'sessions_view_model.dart';

enum _CatalogAction {
  workspace,
  terminal,
  diagnostics,
  voiceSettings,
  disconnect,
}

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    required this.profile,
    required this.viewModel,
    required this.onOpenSession,
    required this.onOpenWorkspace,
    required this.onOpenTerminal,
    required this.onOpenDiagnostics,
    required this.onOpenVoiceSettings,
    required this.onDisconnect,
    super.key,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final ValueChanged<OpenCodeSession> onOpenSession;
  final ValueChanged<List<OpenCodeProject>> onOpenWorkspace;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenDiagnostics;
  final VoidCallback onOpenVoiceSettings;
  final VoidCallback onDisconnect;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  final _searchController = TextEditingController();
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.viewModel.load(widget.profile);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PROMPT', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _OnlineDot(),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    widget.profile.displayOrigin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // No refresh action here: the session list is pull-to-refresh.
          // Secondary destinations live in one menu so a phone-width app bar
          // keeps a single, reachable primary action.
          PopupMenuButton<_CatalogAction>(
            tooltip: 'More actions',
            onSelected: (action) {
              switch (action) {
                case _CatalogAction.workspace:
                  final state = widget.viewModel.value;
                  if (state case SessionsReady(:final projects)) {
                    widget.onOpenWorkspace(projects);
                  }
                case _CatalogAction.terminal:
                  widget.onOpenTerminal();
                case _CatalogAction.diagnostics:
                  widget.onOpenDiagnostics();
                case _CatalogAction.voiceSettings:
                  widget.onOpenVoiceSettings();
                case _CatalogAction.disconnect:
                  widget.onDisconnect();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _CatalogAction.workspace,
                enabled: widget.viewModel.value is SessionsReady,
                child: const ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Browse workspace'),
                ),
              ),
              const PopupMenuItem(
                value: _CatalogAction.terminal,
                child: ListTile(
                  leading: Icon(Icons.terminal_outlined),
                  title: Text('Remote terminal'),
                ),
              ),
              const PopupMenuItem(
                value: _CatalogAction.diagnostics,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Server settings'),
                ),
              ),
              const PopupMenuItem(
                value: _CatalogAction.voiceSettings,
                child: ListTile(
                  leading: Icon(Icons.mic_none_outlined),
                  title: Text('Voice settings'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _CatalogAction.disconnect,
                child: ListTile(
                  leading: Icon(Icons.power_settings_new_rounded),
                  title: Text('Disconnect'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ValueListenableBuilder<SessionsUiState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) {
          return switch (state) {
            SessionsIdle() || SessionsLoading() => const _LoadingCatalog(),
            SessionsEmpty() => _EmptyCatalog(
              onCreate: () => _createSession(const []),
            ),
            SessionsError(:final failure) => _SessionsError(
              failure: failure,
              onRetry: () => widget.viewModel.load(widget.profile),
            ),
            SessionsReady(:final sessions, :final projects) => _buildReady(
              sessions,
              projects,
            ),
          };
        },
      ),
    );
  }

  Widget _buildReady(
    List<OpenCodeSession> sessions,
    List<OpenCodeProject> projects,
  ) {
    final projectIdsWithSessions = sessions
        .map((session) => session.projectId)
        .toSet();
    final filterProjects = projects
        .where((project) => projectIdsWithSessions.contains(project.id))
        .toList(growable: false);
    final selectedProjectId =
        projectIdsWithSessions.contains(_selectedProjectId)
        ? _selectedProjectId
        : null;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = sessions
        .where((session) {
          if (selectedProjectId != null &&
              session.projectId != selectedProjectId) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return session.title.toLowerCase().contains(query) ||
              session.directory.toLowerCase().contains(query) ||
              session.id.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final primary = filtered
        .where((session) => session.parentId?.isNotEmpty != true)
        .toList(growable: false);
    final childrenByParent = <String, int>{};
    for (final session in sessions) {
      final parentId = session.parentId;
      if (parentId != null && parentId.isNotEmpty) {
        childrenByParent.update(
          parentId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }

    return Column(
      children: [
        _CatalogControls(
          searchController: _searchController,
          projects: filterProjects,
          selectedProjectId: selectedProjectId,
          onSelectProject: (id) => setState(() => _selectedProjectId = id),
          onCreate: () => _createSession(projects),
        ),
        Expanded(
          child: primary.isEmpty
              ? _NoMatchingSessions(
                  hasQuery: query.isNotEmpty || selectedProjectId != null,
                  onClear: () {
                    _searchController.clear();
                    setState(() => _selectedProjectId = null);
                  },
                  onCreate: () => _createSession(projects),
                )
              : RefreshIndicator(
                  onRefresh: () => widget.viewModel.load(widget.profile),
                  child: ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
                    itemCount: primary.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = primary[index];
                      return _SessionCard(
                        session: session,
                        childCount: childrenByParent[session.id] ?? 0,
                        onTap: () => widget.onOpenSession(session),
                        onCopyId: () => _copySessionId(session),
                        onRename: () => _renameSession(session),
                        onDelete: () => _deleteSession(session),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _createSession(List<OpenCodeProject> projects) async {
    final request =
        await showModalBottomSheet<({String directory, String title})>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _NewSessionSheet(
            profile: widget.profile,
            viewModel: widget.viewModel,
            projects: projects,
          ),
        );
    if (!mounted || request == null) {
      return;
    }
    final result = await widget.viewModel.create(
      widget.profile,
      request.directory,
      title: request.title,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok<OpenCodeSession, SessionsFailure>(:final value):
        widget.onOpenSession(value);
      case Err<OpenCodeSession, SessionsFailure>(:final failure):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  void _copySessionId(OpenCodeSession session) {
    Clipboard.setData(ClipboardData(text: session.id));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Session ID copied')));
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

class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet({
    required this.profile,
    required this.viewModel,
    required this.projects,
  });

  final ServerProfile profile;
  final SessionsViewModel viewModel;
  final List<OpenCodeProject> projects;

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  late final TextEditingController _directoryController;
  late final TextEditingController _titleController;
  Timer? _debounce;
  List<String> _suggestions = const [];
  SessionsFailure? _suggestionFailure;
  bool _searching = false;
  int _suggestionRevision = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.projects
        .firstWhere(
          (project) => project.id != 'global',
          orElse: () => widget.projects.isEmpty
              ? const OpenCodeProject(id: '', directory: '')
              : widget.projects.first,
        )
        .directory;
    _directoryController = TextEditingController(text: initial)
      ..addListener(_directoryChanged);
    _titleController = TextEditingController();
    _suggestions = widget.projects
        .map((project) => project.directory)
        .where((directory) => directory.isNotEmpty)
        .toSet()
        .toList();
  }

  @override
  void dispose() {
    _suggestionRevision++;
    _debounce?.cancel();
    _directoryController
      ..removeListener(_directoryChanged)
      ..dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _directoryChanged() {
    final revision = ++_suggestionRevision;
    _debounce?.cancel();
    final input = _directoryController.text.trim();
    if (!mounted) return;
    setState(() {
      _searching = false;
      _suggestionFailure = null;
      _suggestions = _knownSuggestions(input);
    });
    if (input.isEmpty || !_isAbsoluteServerPath(input)) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      setState(() {
        _searching = true;
        _suggestionFailure = null;
      });
      final result = await widget.viewModel.suggestDirectories(
        widget.profile,
        input,
      );
      if (!mounted || revision != _suggestionRevision || result == null) return;
      setState(() {
        _searching = false;
        switch (result) {
          case Ok<List<String>, SessionsFailure>(:final value):
            _suggestions = {..._knownSuggestions(input), ...value}.toList()
              ..sort();
          case Err<List<String>, SessionsFailure>(:final failure):
            _suggestionFailure = failure;
        }
      });
    });
  }

  List<String> _knownSuggestions(String input) {
    final normalized = input.toLowerCase();
    return widget.projects
        .map((project) => project.directory)
        .where(
          (directory) =>
              normalized.isEmpty ||
              directory.toLowerCase().startsWith(normalized),
        )
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    final directory = _directoryController.text.trim();
    final valid = _isAbsoluteServerPath(directory);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'New session',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Enter an absolute path on the server. This does not select or copy files from the phone.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _directoryController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Server project path',
                  hintText: '/srv/projects/my-app',
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  errorText: directory.isNotEmpty && !valid
                      ? 'Use an absolute Unix or Windows path.'
                      : null,
                ),
              ),
              if (_suggestionFailure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Directory suggestions unavailable; you can still enter the path manually.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length > 20
                        ? 20
                        : _suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(
                          suggestion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          _directoryController.value = TextEditingValue(
                            text: suggestion,
                            selection: TextSelection.collapsed(
                              offset: suggestion.length,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  hintText: 'What are we working on?',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: valid
                    ? () => Navigator.of(context).pop((
                        directory: directory,
                        title: _titleController.text,
                      ))
                    : null,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Create and open'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isAbsoluteServerPath(String value) =>
    RegExp(r'^/(?:[^/].*)?$').hasMatch(value) ||
    RegExp(r'^(?:\\\\|//)[^\\/]+[\\/][^\\/]+(?:[\\/].*)?$').hasMatch(value) ||
    RegExp(r'^[A-Za-z]:[\\/](?:.*)?$').hasMatch(value);

class _CatalogControls extends StatelessWidget {
  const _CatalogControls({
    required this.searchController,
    required this.projects,
    required this.selectedProjectId,
    required this.onSelectProject,
    required this.onCreate,
  });

  final TextEditingController searchController;
  final List<OpenCodeProject> projects;
  final String? selectedProjectId;
  final ValueChanged<String?> onSelectProject;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search sessions, projects, IDs',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: searchController.clear,
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Clear search',
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'New session',
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: selectedProjectId == null,
                    onSelected: (_) => onSelectProject(null),
                  ),
                  for (final project in projects) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(_projectLabel(project)),
                      selected: selectedProjectId == project.id,
                      onSelected: (_) => onSelectProject(project.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.childCount,
    required this.onTap,
    required this.onCopyId,
    required this.onRename,
    required this.onDelete,
  });

  final OpenCodeSession session;
  final int childCount;
  final VoidCallback onTap;
  final VoidCallback onCopyId;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.terminal_rounded,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title.isEmpty
                          ? 'Untitled session'
                          : session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _directoryName(session.directory),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _MetaLabel(
                          icon: Icons.schedule_rounded,
                          text: _relativeTime(session.updatedAt),
                        ),
                        if (session.changedFiles != null)
                          _MetaLabel(
                            icon: Icons.difference_outlined,
                            text:
                                '${session.changedFiles} files  '
                                '+${session.additions ?? 0} '
                                '-${session.deletions ?? 0}',
                          ),
                        if (childCount > 0)
                          _MetaLabel(
                            icon: Icons.account_tree_outlined,
                            text: '$childCount subagents',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_SessionAction>(
                tooltip: 'Session actions',
                onSelected: (action) {
                  switch (action) {
                    case _SessionAction.copyId:
                      onCopyId();
                    case _SessionAction.rename:
                      onRename();
                    case _SessionAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _SessionAction.copyId,
                    child: ListTile(
                      leading: Icon(Icons.content_copy_outlined),
                      title: Text('Copy session ID'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _SessionAction.rename,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: _SessionAction.delete,
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SessionAction { copyId, rename, delete }

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Server connected',
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LoadingCatalog extends StatelessWidget {
  const _LoadingCatalog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'Loading sessions',
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _NoMatchingSessions extends StatelessWidget {
  const _NoMatchingSessions({
    required this.hasQuery,
    required this.onClear,
    required this.onCreate,
  });

  final bool hasQuery;
  final VoidCallback onClear;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: hasQuery ? Icons.search_off_rounded : Icons.forum_outlined,
      title: hasQuery ? 'No matching sessions' : 'No sessions yet',
      body: hasQuery
          ? 'Try a different search or show every project.'
          : 'Create a session in one of the server projects.',
      action: hasQuery ? ('Clear filters', onClear) : ('New session', onCreate),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.folder_off_outlined,
      title: 'No OpenCode projects',
      body: 'Open a project on the server, then refresh this catalog.',
      action: ('New session', onCreate),
    );
  }
}

class _SessionsError extends StatelessWidget {
  const _SessionsError({required this.failure, required this.onRetry});

  final SessionsFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.sync_problem_rounded,
      title: 'Cannot load sessions',
      body: failure.message,
      action: ('Try again', onRetry),
      error: true,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final (String, VoidCallback?) action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 52,
                color: error
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (action.$2 != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: action.$2, child: Text(action.$1)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _projectLabel(OpenCodeProject project) {
  return project.id == 'global' ? 'Global' : project.name;
}

String _directoryName(String directory) {
  final normalized = directory.replaceAll('\\', '/');
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return segments.isEmpty ? directory : segments.last;
}

String _relativeTime(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inMinutes < 1) {
    return 'just now';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes}m';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours}h';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d';
  }
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}
