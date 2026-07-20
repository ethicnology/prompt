import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/permission_response.dart';
import '../domain/session_execution_state.dart';

class OpenCodeChatService {
  OpenCodeChatService(this._transport);

  final OpenCodeTransport _transport;

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

  /// Sends [text] as a new user message to [session] without waiting for
  /// the assistant's reply. The server responds with an empty `204` once
  /// the message is accepted and generation has started; any other status,
  /// or a non-empty body, is treated as a failure by the caller.
  ///
  /// Never logs [text] or any part of the request/response.
  Future<void> sendPromptAsync(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String text,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/prompt_async?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'parts': [
          {'type': 'text', 'text': text},
        ],
      }),
    );
    if (response.statusCode != 204) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    if (response.body.isNotEmpty) {
      throw const FormatException('Prompt response must be empty.');
    }
  }

  /// Explicitly cancels any active generation or command execution for
  /// [session]. Returns whether the server actually aborted something.
  Future<bool> abortSession(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/abort?$query',
    );
    if (response.statusCode != 200) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! bool) {
      throw const FormatException('Abort response must be a boolean.');
    }
    return decoded;
  }

  /// Responds to a pending tool-call permission with [response], per `POST
  /// /session/{id}/permissions/{permissionID}`. Never logs [permissionId]
  /// or any detail about the permission.
  Future<bool> respondToPermission(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String permissionId,
    PermissionResponse response,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final httpResponse = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/permissions/'
      '${Uri.encodeComponent(permissionId)}?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'response': response.wireValue}),
    );
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
      throw OpenCodeHttpFailure(httpResponse.statusCode);
    }
    final decoded = jsonDecode(httpResponse.body);
    if (decoded is! bool) {
      throw const FormatException('Permission response must be a boolean.');
    }
    return decoded;
  }

  /// Answers a pending question request with [answers], one entry per
  /// question in the original request and in the same order, each a list
  /// of selected option labels and/or typed free-text answers. Per `POST
  /// /question/{requestID}/reply`. Never logs [requestId] or any answer.
  Future<bool> replyToQuestion(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String requestId,
    List<List<String>> answers,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final httpResponse = await _transport.post(
      profile,
      password,
      '/question/${Uri.encodeComponent(requestId)}/reply?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'answers': answers}),
    );
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
      throw OpenCodeHttpFailure(httpResponse.statusCode);
    }
    final decoded = jsonDecode(httpResponse.body);
    if (decoded is! bool) {
      throw const FormatException('Question reply response must be a boolean.');
    }
    return decoded;
  }

  /// Rejects a pending question request outright, per `POST /question/
  /// {requestID}/reject`. Never logs [requestId].
  Future<bool> rejectQuestion(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String requestId,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final httpResponse = await _transport.post(
      profile,
      password,
      '/question/${Uri.encodeComponent(requestId)}/reject?$query',
    );
    if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
      throw OpenCodeHttpFailure(httpResponse.statusCode);
    }
    final decoded = jsonDecode(httpResponse.body);
    if (decoded is! bool) {
      throw const FormatException(
        'Question reject response must be a boolean.',
      );
    }
    return decoded;
  }

  /// Fetches the execution state of every session known to the server for
  /// [directory], keyed by session id. A session with no ongoing or
  /// retrying work may simply be absent from the response.
  Future<Map<String, SessionExecutionState>> fetchSessionStatuses(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final query = Uri(queryParameters: {'directory': directory}).query;
    final response = await _get(profile, password, '/session/status?$query');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Session status response must be a map.');
    }
    final statuses = <String, SessionExecutionState>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Session status entry is malformed.');
      }
      final state = _mapSessionExecutionState(value);
      if (state == null) {
        throw const FormatException('Session status entry is malformed.');
      }
      statuses[entry.key] = state;
    }
    return statuses;
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

/// Maps a raw `SessionStatus` JSON object, as returned by both `GET
/// /session/status` and the `session.status` SSE event, to a typed
/// [SessionExecutionState]. Returns `null` for a malformed or unrecognized
/// payload.
SessionExecutionState? _mapSessionExecutionState(Map<String, dynamic> json) {
  final type = json['type'];
  switch (type) {
    case 'idle':
      return const SessionIdle();
    case 'busy':
      return const SessionBusy();
    case 'retry':
      final attempt = json['attempt'];
      final message = json['message'];
      final next = json['next'];
      if (attempt is! num || message is! String || next is! num) {
        return null;
      }
      return SessionRetrying(
        attempt: attempt.toInt(),
        nextAttemptAtMillis: next.toInt(),
      );
    default:
      return null;
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
