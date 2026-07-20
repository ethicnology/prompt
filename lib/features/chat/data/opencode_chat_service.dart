import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/opencode_authorization.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/data/opencode_sessions_service.dart';
import '../../sessions/domain/open_code_session.dart';

class OpenCodeChatService {
  OpenCodeChatService(this._client);

  final http.Client _client;

  Future<List<OpenCodeMessageRecord>> listMessages(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final query = Uri(
      queryParameters: {'directory': session.directory, 'limit': '100'},
    ).query;
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/message?$query',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Messages response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeMessageRecord.fromJson)
        .toList(growable: false);
  }

  Future<http.Response> _get(
    ServerProfile profile,
    String? password,
    String path,
  ) async {
    final response = await _client
        .get(
          profile.origin.resolve(path),
          headers: openCodeAuthorizationHeaders(
            username: profile.username,
            password: password,
          ),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    return response;
  }
}

class OpenCodeMessageRecord {
  const OpenCodeMessageRecord({
    required this.id,
    required this.role,
    required this.createdAtMillis,
    required this.text,
  });

  factory OpenCodeMessageRecord.fromJson(Map<String, dynamic> json) {
    final info = json['info'];
    final parts = json['parts'];
    if (info is! Map<String, dynamic> || parts is! List) {
      throw const FormatException('Message is missing its info or parts.');
    }
    final id = info['id'];
    final role = info['role'];
    final time = info['time'];
    if (id is! String || role is! String || time is! Map<String, dynamic>) {
      throw const FormatException('Message has invalid required fields.');
    }
    final createdAt = time['created'];
    if (createdAt is! num) {
      throw const FormatException('Message is missing its creation time.');
    }
    final text = parts
        .whereType<Map<String, dynamic>>()
        .where((part) => part['type'] == 'text')
        .map((part) => part['text'])
        .whereType<String>()
        .join();
    return OpenCodeMessageRecord(
      id: id,
      role: role,
      createdAtMillis: createdAt.toInt(),
      text: text,
    );
  }

  final String id;
  final String role;
  final int createdAtMillis;
  final String text;
}
