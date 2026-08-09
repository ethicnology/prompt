class OpenCodeSession {
  const OpenCodeSession({
    required this.id,
    required this.projectId,
    required this.directory,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.changedFiles,
    this.additions,
    this.deletions,
    this.shareUrl,
  });

  final String id;
  final String projectId;
  final String directory;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? parentId;
  final int? changedFiles;
  final int? additions;
  final int? deletions;
  final String? shareUrl;
}
