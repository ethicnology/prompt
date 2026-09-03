import 'package:flutter/foundation.dart';

enum DiffRowKind { context, addition, deletion, meta }

@immutable
class DiffRow {
  const DiffRow({
    required this.id,
    required this.kind,
    required this.content,
    required this.prefix,
    this.oldLine,
    this.newLine,
  });

  final String id;
  final DiffRowKind kind;
  final String content;
  final String prefix;
  final int? oldLine;
  final int? newLine;
}

@immutable
class DiffHunk {
  const DiffHunk({
    required this.id,
    required this.header,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.rows,
  });

  final String id;
  final String header;
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffRow> rows;
}

@immutable
class DiffFile {
  DiffFile({
    required this.id,
    required this.path,
    required List<DiffHunk> hunks,
    this.oldPath,
    List<DiffRow> metadata = const <DiffRow>[],
  }) : hunks = hunks,
       metadata = metadata,
       // Built once here rather than on each access: the viewer reads this for
       // the item count and again for every row it builds, so recomputing it
       // made rendering a file quadratic in its number of lines.
       rows = List<DiffRow>.unmodifiable(<DiffRow>[
         ...metadata,
         for (final hunk in hunks) ...hunk.rows,
       ]);

  final String id;
  final String path;
  final String? oldPath;
  final List<DiffRow> metadata;
  final List<DiffHunk> hunks;

  /// Flattened rows in display order.
  final List<DiffRow> rows;
}

@immutable
class DiffDocument {
  const DiffDocument({required this.files, this.warnings = const <String>[]});

  final List<DiffFile> files;
  final List<String> warnings;
}
