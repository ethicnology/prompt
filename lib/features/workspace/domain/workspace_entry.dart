class WorkspaceEntry {
  const WorkspaceEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.isIgnored,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final bool isIgnored;
}

class WorkspaceFileContent {
  const WorkspaceFileContent.text(this.value) : isText = true;

  const WorkspaceFileContent.binary() : isText = false, value = null;

  final bool isText;
  final String? value;
}

enum WorkspaceFileStatus { added, deleted, modified }

class WorkspaceStatusEntry {
  const WorkspaceStatusEntry({
    required this.path,
    required this.status,
    required this.added,
    required this.removed,
  });

  final String path;
  final WorkspaceFileStatus status;
  final int added;
  final int removed;
}

class WorkspaceVcsSummary {
  const WorkspaceVcsSummary(this.branch);

  final String branch;
}

class WorkspaceSnapshot {
  const WorkspaceSnapshot({
    required this.entries,
    required this.status,
    required this.vcs,
  });

  final List<WorkspaceEntry> entries;
  final List<WorkspaceStatusEntry> status;
  final WorkspaceVcsSummary vcs;
}

enum WorkspaceSearchKind { text, file, symbol }

sealed class WorkspaceSearchResult {
  const WorkspaceSearchResult(this.path);

  final String path;
}

class WorkspaceTextSearchResult extends WorkspaceSearchResult {
  const WorkspaceTextSearchResult({
    required String path,
    required this.line,
    required this.lineNumber,
    required this.absoluteOffset,
    required this.matches,
  }) : super(path);

  final String line;
  final int lineNumber;
  final int absoluteOffset;
  final List<WorkspaceTextSubmatch> matches;
}

class WorkspaceTextSubmatch {
  const WorkspaceTextSubmatch({required this.start, required this.end});

  final int start;
  final int end;
}

class WorkspaceFileSearchResult extends WorkspaceSearchResult {
  const WorkspaceFileSearchResult({required String path}) : super(path);
}

class WorkspaceSymbolSearchResult extends WorkspaceSearchResult {
  const WorkspaceSymbolSearchResult({
    required String path,
    required this.name,
    required this.kind,
    required this.line,
    required this.character,
  }) : super(path);

  final String name;
  final int kind;
  final int line;
  final int character;
}
