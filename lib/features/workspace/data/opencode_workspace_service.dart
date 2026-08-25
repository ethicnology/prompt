import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/workspace_entry.dart';

class OpenCodeWorkspaceService {
  OpenCodeWorkspaceService(this._transport);

  final OpenCodeTransport _transport;

  Future<List<WorkspaceEntry>> listFiles(
    ServerProfile profile,
    String? password, {
    required String directory,
    required String path,
  }) async {
    final response = await _get(
      profile,
      password,
      '/file?${Uri(queryParameters: {'directory': directory, 'path': path}).query}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('File list is malformed.');
    }
    return decoded.map<WorkspaceEntry>(_entry).toList(growable: false);
  }

  Future<WorkspaceFileContent> readFile(
    ServerProfile profile,
    String? password, {
    required String directory,
    required String path,
  }) async {
    final response = await _get(
      profile,
      password,
      '/file/content?${Uri(queryParameters: {'directory': directory, 'path': path}).query}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['type'] is! String) {
      throw const FormatException('File content is malformed.');
    }
    return switch (decoded['type']) {
      'text' when decoded['content'] is String => WorkspaceFileContent.text(
        decoded['content'] as String,
      ),
      'binary' => const WorkspaceFileContent.binary(),
      _ => throw const FormatException('File content is malformed.'),
    };
  }

  Future<List<WorkspaceStatusEntry>> status(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final response = await _get(
      profile,
      password,
      '/file/status?${Uri(queryParameters: {'directory': directory}).query}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('File status is malformed.');
    }
    return decoded.map<WorkspaceStatusEntry>(_status).toList(growable: false);
  }

  Future<WorkspaceVcsSummary> vcs(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final response = await _get(
      profile,
      password,
      '/vcs?${Uri(queryParameters: {'directory': directory}).query}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['branch'] is! String) {
      throw const FormatException('VCS response is malformed.');
    }
    return WorkspaceVcsSummary(decoded['branch'] as String);
  }

  Future<List<WorkspaceSearchResult>> search(
    ServerProfile profile,
    String? password, {
    required String directory,
    required WorkspaceSearchKind kind,
    required String query,
  }) async {
    final parameters = <String, String>{
      'directory': directory,
      kind == WorkspaceSearchKind.text ? 'pattern' : 'query': query,
    };
    final path = switch (kind) {
      WorkspaceSearchKind.text => '/find',
      WorkspaceSearchKind.file => '/find/file',
      WorkspaceSearchKind.symbol => '/find/symbol',
    };
    final response = await _get(
      profile,
      password,
      '$path?${Uri(queryParameters: parameters).query}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Search response is malformed.');
    }
    return switch (kind) {
      WorkspaceSearchKind.text =>
        decoded.map<WorkspaceSearchResult>(_textMatch).toList(growable: false),
      WorkspaceSearchKind.file =>
        decoded.map<WorkspaceSearchResult>(_fileMatch).toList(growable: false),
      WorkspaceSearchKind.symbol =>
        decoded
            .map<WorkspaceSearchResult>(_symbolMatch)
            .toList(growable: false),
    };
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

  WorkspaceEntry _entry(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['name'] is! String ||
        value['absolute'] is! String ||
        value['type'] is! String ||
        value['ignored'] is! bool) {
      throw const FormatException('File entry is malformed.');
    }
    final type = value['type'];
    if (type != 'file' && type != 'directory') {
      throw const FormatException('File entry is malformed.');
    }
    return WorkspaceEntry(
      name: value['name'] as String,
      path: value['absolute'] as String,
      isDirectory: type == 'directory',
      isIgnored: value['ignored'] as bool,
    );
  }

  WorkspaceStatusEntry _status(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['path'] is! String ||
        value['status'] is! String ||
        value['added'] is! num ||
        value['removed'] is! num) {
      throw const FormatException('File status is malformed.');
    }
    final status = switch (value['status']) {
      'added' => WorkspaceFileStatus.added,
      'deleted' => WorkspaceFileStatus.deleted,
      'modified' => WorkspaceFileStatus.modified,
      _ => throw const FormatException('File status is malformed.'),
    };
    return WorkspaceStatusEntry(
      path: value['path'] as String,
      status: status,
      added: (value['added'] as num).toInt(),
      removed: (value['removed'] as num).toInt(),
    );
  }

  WorkspaceTextSearchResult _textMatch(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['path'] is! Map<String, dynamic> ||
        value['lines'] is! Map<String, dynamic> ||
        (value['path'] as Map<String, dynamic>)['text'] is! String ||
        (value['lines'] as Map<String, dynamic>)['text'] is! String ||
        value['line_number'] is! num ||
        value['absolute_offset'] is! num ||
        value['submatches'] is! List) {
      throw const FormatException('Text search result is malformed.');
    }
    final matches = (value['submatches'] as List)
        .map((submatch) {
          if (submatch is! Map<String, dynamic> ||
              submatch['start'] is! num ||
              submatch['end'] is! num) {
            throw const FormatException('Text search result is malformed.');
          }
          return WorkspaceTextSubmatch(
            start: (submatch['start'] as num).toInt(),
            end: (submatch['end'] as num).toInt(),
          );
        })
        .toList(growable: false);
    return WorkspaceTextSearchResult(
      path: (value['path'] as Map<String, dynamic>)['text'] as String,
      line: (value['lines'] as Map<String, dynamic>)['text'] as String,
      lineNumber: (value['line_number'] as num).toInt(),
      absoluteOffset: (value['absolute_offset'] as num).toInt(),
      matches: matches,
    );
  }

  WorkspaceFileSearchResult _fileMatch(Object? value) {
    if (value is! String) {
      throw const FormatException('File search result is malformed.');
    }
    return WorkspaceFileSearchResult(path: value);
  }

  WorkspaceSymbolSearchResult _symbolMatch(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['name'] is! String ||
        value['kind'] is! num ||
        value['location'] is! Map<String, dynamic>) {
      throw const FormatException('Symbol search result is malformed.');
    }
    final location = value['location'] as Map<String, dynamic>;
    final range = location['range'];
    if (location['uri'] is! String ||
        range is! Map<String, dynamic> ||
        range['start'] is! Map<String, dynamic> ||
        (range['start'] as Map<String, dynamic>)['line'] is! num ||
        (range['start'] as Map<String, dynamic>)['character'] is! num) {
      throw const FormatException('Symbol search result is malformed.');
    }
    final start = range['start'] as Map<String, dynamic>;
    return WorkspaceSymbolSearchResult(
      path: location['uri'] as String,
      name: value['name'] as String,
      kind: (value['kind'] as num).toInt(),
      line: (start['line'] as num).toInt(),
      character: (start['character'] as num).toInt(),
    );
  }
}
