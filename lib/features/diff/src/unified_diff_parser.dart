import 'diff_model.dart';

/// A forgiving parser for the unified diff format. Invalid lines become meta
/// rows so that displaying an incomplete server response never throws.
class UnifiedDiffParser {
  const UnifiedDiffParser._();

  static DiffDocument parse(String patch) {
    final lines = patch.split('\n');
    final files = <_FileBuilder>[_FileBuilder('patch')];
    var current = files.first;
    _HunkBuilder? hunk;
    final warnings = <String>[];
    var fileNumber = 0;
    var rowNumber = 0;

    void finishHunk() {
      if (hunk != null) {
        current.hunks.add(hunk!.build(current.id, current.hunks.length));
      }
      hunk = null;
    }

    void finishFile() {
      finishHunk();
      if (current.hasMeaningfulContent || files.length > 1) {
        current.path = current.path == 'patch' ? 'Untitled file' : current.path;
      }
    }

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      if (line.isEmpty &&
          lineIndex == lines.length - 1 &&
          patch.endsWith('\n')) {
        continue;
      }
      if (line.startsWith('diff --git ')) {
        finishFile();
        current = _FileBuilder('file-${++fileNumber}');
        files.add(current);
        continue;
      }
      final header = _hunkPattern.firstMatch(line);
      if (header != null) {
        finishHunk();
        hunk = _HunkBuilder(
          header: line,
          oldStart: int.parse(header.group(1)!),
          oldCount: int.tryParse(header.group(2) ?? '') ?? 1,
          newStart: int.parse(header.group(3)!),
          newCount: int.tryParse(header.group(4) ?? '') ?? 1,
        );
        current.hasMeaningfulContent = true;
        continue;
      }
      if (line.startsWith('--- ')) {
        current.oldPath = _pathFromHeader(line);
        current.hasMeaningfulContent = true;
        continue;
      }
      if (line.startsWith('+++ ')) {
        current.path = _pathFromHeader(line);
        current.hasMeaningfulContent = true;
        continue;
      }
      if (hunk != null && line.isNotEmpty && ' +-'.contains(line[0])) {
        final prefix = line[0];
        final content = line.substring(1);
        final kind = prefix == '+'
            ? DiffRowKind.addition
            : prefix == '-'
            ? DiffRowKind.deletion
            : DiffRowKind.context;
        hunk!.add(
          DiffRow(
            id: '${current.id}-row-${rowNumber++}',
            kind: kind,
            content: content,
            prefix: prefix,
            oldLine: kind == DiffRowKind.addition ? null : hunk!.oldLine,
            newLine: kind == DiffRowKind.deletion ? null : hunk!.newLine,
          ),
        );
        continue;
      }
      if (line == r'\ No newline at end of file') {
        final row = DiffRow(
          id: '${current.id}-row-${rowNumber++}',
          kind: DiffRowKind.meta,
          content: line,
          prefix: '',
        );
        if (hunk == null) {
          current.metadata.add(row);
        } else {
          hunk!.rows.add(row);
        }
        continue;
      }
      if (line.isNotEmpty || hunk == null) {
        current.metadata.add(
          DiffRow(
            id: '${current.id}-meta-${rowNumber++}',
            kind: DiffRowKind.meta,
            content: line,
            prefix: '',
          ),
        );
      } else {
        // Empty context lines are valid and have a space prefix in a patch.
        hunk!.add(
          DiffRow(
            id: '${current.id}-row-${rowNumber++}',
            kind: DiffRowKind.context,
            content: '',
            prefix: ' ',
            oldLine: hunk!.oldLine,
            newLine: hunk!.newLine,
          ),
        );
      }
    }
    finishFile();
    final meaningful = files
        .where((file) => file.hasMeaningfulContent)
        .map((f) => f.build())
        .toList();
    if (meaningful.isEmpty && patch.isNotEmpty) {
      warnings.add('No unified diff content was found.');
    }
    return DiffDocument(
      files: List.unmodifiable(meaningful),
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Parses one file's patch and namespaces every identifier by [path].
  ///
  /// [parse] numbers files, hunks and rows from scratch on each call, so a
  /// caller that parses several patches separately and shows them together —
  /// which is how a review composes its diff — would give every file the same
  /// id. Sibling widgets would then carry duplicate keys and the viewer would
  /// fail to build, and collapsing one file would collapse all of them.
  ///
  /// A server patch normally opens with its own `diff --git` header, so the
  /// path is usually already known; [path] stays authoritative because it is
  /// the one the snapshot is keyed by.
  static DiffDocument parseFile(String path, String patch) {
    final document = parse(patch);
    final prefix = 'file-${path.hashCode}';
    final single = document.files.length == 1;
    return DiffDocument(
      files: [
        for (var index = 0; index < document.files.length; index++)
          _withNamespacedIds(
            document.files[index],
            id: single ? prefix : '$prefix-$index',
            path: single ? path : document.files[index].path,
          ),
      ],
      warnings: document.warnings,
    );
  }

  static DiffFile _withNamespacedIds(
    DiffFile file, {
    required String id,
    required String path,
  }) {
    // Re-key against the parsed source rows rather than the file's display
    // rows, so this stays correct while the display order also carries
    // synthesised entries that no hunk owns.
    final source = <DiffRow>[
      ...file.metadata,
      for (final hunk in file.hunks) ...hunk.rows,
    ];
    final rows = [
      for (var index = 0; index < source.length; index++)
        DiffRow(
          id: '$id-row-$index',
          kind: source[index].kind,
          content: source[index].content,
          prefix: source[index].prefix,
          oldLine: source[index].oldLine,
          newLine: source[index].newLine,
        ),
    ];
    final byOldId = {
      for (var index = 0; index < source.length; index++)
        source[index].id: rows[index],
    };
    return DiffFile(
      id: id,
      path: path,
      oldPath: file.oldPath,
      metadata: [for (final row in file.metadata) byOldId[row.id]!],
      hunks: [
        for (var index = 0; index < file.hunks.length; index++)
          DiffHunk(
            id: '$id-hunk-$index',
            header: file.hunks[index].header,
            oldStart: file.hunks[index].oldStart,
            oldCount: file.hunks[index].oldCount,
            newStart: file.hunks[index].newStart,
            newCount: file.hunks[index].newCount,
            rows: [for (final row in file.hunks[index].rows) byOldId[row.id]!],
          ),
      ],
    );
  }

  static String _pathFromHeader(String line) {
    final path = line.substring(4).split('\t').first;
    if (path == '/dev/null') return path;
    return path.startsWith('a/') || path.startsWith('b/')
        ? path.substring(2)
        : path;
  }

  static final _hunkPattern = RegExp(
    r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
  );
}

/// Short alias for callers that do not need to name the format.
typedef DiffParser = UnifiedDiffParser;

DiffDocument parseUnifiedDiff(String patch) => UnifiedDiffParser.parse(patch);

class _FileBuilder {
  _FileBuilder(this.id) : path = 'patch';
  final String id;
  String path;
  String? oldPath;
  final metadata = <DiffRow>[];
  final hunks = <DiffHunk>[];
  bool hasMeaningfulContent = false;
  DiffFile build() => DiffFile(
    id: id,
    path: path,
    oldPath: oldPath,
    metadata: List.unmodifiable(metadata),
    hunks: List.unmodifiable(hunks),
  );
}

class _HunkBuilder {
  _HunkBuilder({
    required this.header,
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
  });
  final String header;
  final int oldStart, oldCount, newStart, newCount;
  final rows = <DiffRow>[];
  int oldLineOffset = 0, newLineOffset = 0;
  int get oldLine => oldStart + oldLineOffset;
  int get newLine => newStart + newLineOffset;
  void add(DiffRow row) {
    rows.add(row);
    if (row.kind != DiffRowKind.addition) oldLineOffset++;
    if (row.kind != DiffRowKind.deletion) newLineOffset++;
  }

  DiffHunk build(String fileId, int ordinal) => DiffHunk(
    id: '$fileId-hunk-$ordinal',
    header: header,
    oldStart: oldStart,
    oldCount: oldCount,
    newStart: newStart,
    newCount: newCount,
    rows: List.unmodifiable(rows),
  );
}
