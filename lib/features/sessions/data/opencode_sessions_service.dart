import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../domain/open_code_session.dart';

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
    final path = directory.isEmpty
        ? '/session'
        : '/session?${Uri(queryParameters: {
            'directory': directory,
            // A project can retain sessions from a renamed or secondary
            // worktree. Ask OpenCode for its complete project catalog rather
            // than filtering it to the current worktree path.
            'scope': 'project',
          }).query}';
    final response = await _get(profile, password, path);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Sessions response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeSessionRecord.fromJson)
        .toList(growable: false);
  }

  Future<OpenCodeSessionRecord> createSession(
    ServerProfile profile,
    String? password,
    String directory, {
    String? title,
  }) async {
    final query = Uri(queryParameters: {'directory': directory}).query;
    final normalizedTitle = title?.trim();
    final response = await _transport.post(
      profile,
      password,
      '/session?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        if (normalizedTitle != null && normalizedTitle.isNotEmpty)
          'title': normalizedTitle,
      }),
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Created session response must be an object.',
      );
    }
    return OpenCodeSessionRecord.fromJson(decoded);
  }

  Future<void> renameSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String title,
  ) async {
    final response = await _transport.patch(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}?${Uri(queryParameters: {'directory': session.directory}).query}',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'title': title}),
    );
    _requireSuccess(response);
  }

  Future<void> deleteSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _transport.delete(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}?${Uri(queryParameters: {'directory': session.directory}).query}',
    );
    _requireSuccess(response);
  }

  Future<bool> abortSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/abort?${Uri(queryParameters: {'directory': session.directory}).query}',
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! bool) {
      throw const FormatException('Abort response must be a boolean.');
    }
    return decoded;
  }

  Future<OpenCodeSessionRecord> forkSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) => _postSession(profile, password, session, 'fork');

  Future<OpenCodeSessionRecord> shareSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) => _postSession(profile, password, session, 'share');

  Future<void> unshareSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _transport.delete(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/share?'
      '${Uri(queryParameters: {'directory': session.directory}).query}',
    );
    _requireSuccess(response);
  }

  Future<bool> revertMessage(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String messageId,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/revert?'
      '${Uri(queryParameters: {'directory': session.directory}).query}',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'messageID': messageId}),
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! bool) {
      throw const FormatException('Revert response must be a boolean.');
    }
    return decoded;
  }

  Future<OpenCodeSessionRecord> _postSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String action,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/$action?'
      '${Uri(queryParameters: {'directory': session.directory}).query}',
      headers: const {'content-type': 'application/json'},
    );
    _requireSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$action response must be a session.');
    }
    return OpenCodeSessionRecord.fromJson(decoded);
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _transport.get(profile, password, path);
    _requireSuccess(response);
    return response;
  }

  void _requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
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
    this.shareUrl,
    this.modelProviderId,
    this.modelId,
    this.agentName,
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
    final share = json['share'];
    final shareMap = share is Map<String, dynamic> ? share : null;
    final model = json['model'];
    final modelMap = model is Map<String, dynamic> ? model : null;
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
      shareUrl: shareMap?['url'] as String?,
      modelProviderId: modelMap?['providerID'] as String?,
      modelId: modelMap?['id'] as String?,
      agentName: json['agent'] as String?,
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
  final String? shareUrl;
  final String? modelProviderId;
  final String? modelId;
  final String? agentName;
}
