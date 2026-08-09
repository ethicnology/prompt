class OpenCodeProject {
  const OpenCodeProject({required this.id, required this.directory});

  final String id;
  final String directory;

  String get name {
    final normalized = directory.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    return segments.isEmpty ? directory : segments.last;
  }
}
