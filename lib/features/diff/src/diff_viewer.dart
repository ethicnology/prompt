import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:prompt/core/ui/prompt_color_tokens.dart';

import 'diff_model.dart';
import 'syntax_highlighter.dart';

class DiffViewer extends StatefulWidget {
  const DiffViewer({required this.document, super.key});
  final DiffDocument document;
  @override
  State<DiffViewer> createState() => _DiffViewerState();
}

class _DiffViewerState extends State<DiffViewer> {
  final _expanded = <String, bool>{};
  final _wrapped = <String, bool>{};

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Material(
      color: Colors.transparent,
      child: SizedBox(
        width: constraints.maxWidth,
        child: CustomScrollView(
          key: const ValueKey('diff-scroll'),
          slivers: [
            for (final file in widget.document.files) ...[
              SliverToBoxAdapter(
                child: _FileHeader(
                  file: file,
                  expanded: _expanded[file.id] ?? true,
                  onToggle: () => setState(
                    () => _expanded[file.id] = !(_expanded[file.id] ?? true),
                  ),
                ),
              ),
              if (_expanded[file.id] ?? true)
                SliverList.builder(
                  key: ValueKey('diff-rows-${file.id}'),
                  itemCount: file.rows.length,
                  itemBuilder: (context, index) {
                    final row = file.rows[index];
                    return _DiffRowView(
                      key: ValueKey('diff-row-${row.id}'),
                      row: row,
                      wrapped: _wrapped[row.id] ?? false,
                      onWrap: () => setState(
                        () => _wrapped[row.id] = !(_wrapped[row.id] ?? false),
                      ),
                      path: file.path,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.file,
    required this.expanded,
    required this.onToggle,
  });
  final DiffFile file;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          button: true,
          toggled: expanded,
          label: '${file.path}, ${expanded ? 'expanded' : 'collapsed'}',
          onTap: onToggle,
          child: ListTile(
            key: ValueKey('diff-file-${file.id}'),
            dense: true,
            title: Text(file.path),
            subtitle: file.oldPath == null
                ? null
                : Text('from ${file.oldPath}'),
            trailing: IconButton(
              key: ValueKey('diff-file-toggle-${file.id}'),
              tooltip: expanded ? 'Collapse file' : 'Expand file',
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiffRowView extends StatelessWidget {
  const _DiffRowView({
    super.key,
    required this.row,
    required this.wrapped,
    required this.onWrap,
    required this.path,
  });
  final DiffRow row;
  final bool wrapped;
  final VoidCallback onWrap;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<PromptTokens>();
    final background = row.kind == DiffRowKind.addition
        ? tokens?.diffAdd ?? Colors.green.withValues(alpha: .12)
        : row.kind == DiffRowKind.deletion
        ? tokens?.diffDelete ?? Colors.red.withValues(alpha: .12)
        : Colors.transparent;
    final base =
        theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace') ??
        const TextStyle(fontFamily: 'monospace');
    final spans = row.kind == DiffRowKind.meta
        ? <InlineSpan>[TextSpan(text: row.content, style: base)]
        : <InlineSpan>[
            TextSpan(text: row.content.isEmpty ? '' : row.content, style: base),
          ];
    final source = highlighterForPath(
      path,
    ).highlight(row.content, base, theme.colorScheme.primary);
    return Semantics(
      container: true,
      label: '${row.kind.name} line ${row.newLine ?? row.oldLine ?? ''}',
      hint: wrapped ? 'Tap to unwrap line' : 'Tap to wrap line',
      customSemanticsActions: {
        CustomSemanticsAction(label: wrapped ? 'Unwrap line' : 'Wrap line'):
            onWrap,
      },
      child: DecoratedBox(
        key: ValueKey('diff-row-background-${row.id}'),
        decoration: BoxDecoration(color: background),
        child: InkWell(
          key: ValueKey('diff-row-surface-${row.id}'),
          onTap: row.kind == DiffRowKind.meta ? null : onWrap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  '${row.oldLine ?? ''}',
                  textAlign: TextAlign.right,
                  style: base.copyWith(color: theme.hintColor),
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '${row.newLine ?? ''}',
                  textAlign: TextAlign.right,
                  style: base.copyWith(color: theme.hintColor),
                ),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  row.prefix,
                  style: base.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: wrapped
                    ? SelectableText.rich(
                        TextSpan(
                          children: row.kind == DiffRowKind.meta
                              ? spans
                              : source,
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText.rich(
                          TextSpan(
                            children: row.kind == DiffRowKind.meta
                                ? spans
                                : source,
                          ),
                        ),
                      ),
              ),
              IconButton(
                key: ValueKey('diff-wrap-${row.id}'),
                tooltip: wrapped ? 'Unwrap line' : 'Wrap line',
                icon: Icon(wrapped ? Icons.wrap_text : Icons.notes, size: 18),
                onPressed: row.kind == DiffRowKind.meta ? null : onWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
