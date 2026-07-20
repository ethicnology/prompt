import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';

class OpenCodeSessionsService {
  OpenCodeSessionsService(this._transport);

  final OpenCodeTransport _transport;

  Future<List<OpenCodeProjectRecord>> listProjects(
    ServerProfile profile,
    String? password,
  ) async {
    final response = await _get(profile, password, '/project');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Projects response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeProjectRecord.fromJson)
        .toList(growable: false);
  }

  Future<List<OpenCodeSessionRecord>> listSessions(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final query = Uri(queryParameters: {'directory': directory}).query;
    final response = await _get(profile, password, '/session?$query');
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Sessions response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeSessionRecord.fromJson)
        .toList(growable: false);
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _transport.get(profile, password, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    return response;
  }
}

class OpenCodeProjectRecord {
  const OpenCodeProjectRecord({required this.id, required this.worktree});

  factory OpenCodeProjectRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final worktree = json['worktree'];
    if (id is! String || worktree is! String) {
      throw const FormatException('Project is missing an id or worktree.');
    }
    return OpenCodeProjectRecord(id: id, worktree: worktree);
  }

  final String id;
  final String worktree;
}

class OpenCodeSessionRecord {
  const OpenCodeSessionRecord({
    required this.id,
    required this.projectId,
    required this.directory,
    required this.title,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.parentId,
    this.changedFiles,
    this.additions,
    this.deletions,
  });

  factory OpenCodeSessionRecord.fromJson(Map<String, dynamic> json) {
    final time = json['time'];
    if (time is! Map<String, dynamic>) {
      throw const FormatException('Session is missing its timestamps.');
    }
    final id = json['id'];
    final projectId = json['projectID'];
    final directory = json['directory'];
    final title = json['title'];
    final createdAt = time['created'];
    final updatedAt = time['updated'];
    if (id is! String ||
        projectId is! String ||
        directory is! String ||
        title is! String ||
        createdAt is! num ||
        updatedAt is! num) {
      throw const FormatException('Session has invalid required fields.');
    }

    final summary = json['summary'];
    final summaryMap = summary is Map<String, dynamic> ? summary : null;
    return OpenCodeSessionRecord(
      id: id,
      projectId: projectId,
      directory: directory,
      title: title,
      createdAtMillis: createdAt.toInt(),
      updatedAtMillis: updatedAt.toInt(),
      parentId: json['parentID'] as String?,
      changedFiles: summaryMap?['files'] as int?,
      additions: summaryMap?['additions'] as int?,
      deletions: summaryMap?['deletions'] as int?,
    );
  }

  final String id;
  final String projectId;
  final String directory;
  final String title;
  final int createdAtMillis;
  final int updatedAtMillis;
  final String? parentId;
  final int? changedFiles;
  final int? additions;
  final int? deletions;
}
