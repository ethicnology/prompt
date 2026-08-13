import 'package:flutter/material.dart';

import '../../domain/session_artifacts.dart';

/// Shows the todos and file diffs OpenCode reports for the active session.
class SessionArtifactsPanel extends StatelessWidget {
  const SessionArtifactsPanel({
    required this.state,
    required this.onRefresh,
    super.key,
  });

  final SessionArtifactsState state;
  final Future<void> Function({String? messageId}) onRefresh;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Session artifacts',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Session artifacts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            switch (state) {
              SessionArtifactsLoading() => Padding(
                padding: const EdgeInsets.all(12),
                child: Semantics(
                  label: 'Loading session artifacts',
                  child: const CircularProgressIndicator(),
                ),
              ),
              SessionArtifactsError(:final failure) => Row(
                children: [
                  Expanded(child: Text(failure.message)),
                  TextButton(onPressed: onRefresh, child: const Text('Retry')),
                ],
              ),
              SessionArtifactsReady(:final todos, :final diffs) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Todos (${todos.length}) · Changed files (${diffs.length})',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: onRefresh,
                        tooltip: 'Refresh session artifacts',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (todos.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No todos reported for this session.'),
                    )
                  else
                    for (final todo in todos) _TodoRow(todo: todo),
                  if (diffs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No changed files reported for this session.',
                      ),
                    )
                  else
                    for (final diff in diffs) _DiffRow(diff: diff),
                ],
              ),
            },
          ],
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.todo});

  final SessionTodo todo;

  @override
  Widget build(BuildContext context) {
    final complete = todo.status == SessionTodoStatus.completed;
    return Semantics(
      label:
          '${todo.content}, ${todo.status.name}, ${todo.priority.name} priority',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          complete ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        ),
        title: SelectableText(
          todo.content,
          style: complete
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          '${_todoStatusLabel(todo.status)} · ${todo.priority.name}',
        ),
      ),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.diff});

  final SessionFileDiff diff;

  @override
  Widget build(BuildContext context) {
    final counters = '+${diff.additions} · -${diff.deletions}';
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: SelectableText(diff.file.isEmpty ? 'Changed file' : diff.file),
      subtitle: Text(
        diff.status == null ? counters : '${diff.status} · $counters',
      ),
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SelectableText(
            diff.patch.isEmpty
                ? 'The server reported no patch for this file.'
                : diff.patch,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

String _todoStatusLabel(SessionTodoStatus status) => switch (status) {
  SessionTodoStatus.pending => 'Pending',
  SessionTodoStatus.inProgress => 'In progress',
  SessionTodoStatus.completed => 'Completed',
  SessionTodoStatus.cancelled => 'Cancelled',
};
