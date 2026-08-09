import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../../queue/domain/prompt_execution_options.dart';
import '../../queue/domain/queued_prompt.dart';
import '../domain/conversation_event.dart';
import '../domain/pending_approval.dart';
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

  Future<List<OpenCodeTodoRecord>> listTodos(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/todo',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Todo response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeTodoRecord.fromJson)
        .toList(growable: false);
  }

  Future<List<OpenCodeFileDiffRecord>> listDiffs(
    ServerProfile profile,
    String? password,
    OpenCodeSession session, {
    String? messageId,
  }) async {
    final query = Uri(queryParameters: {'messageID': ?messageId}).query;
    final response = await _get(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/diff'
      '${query.isEmpty ? '' : '?$query'}',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Diff response must be a list.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(OpenCodeFileDiffRecord.fromJson)
        .toList(growable: false);
  }

  /// Sends [text] as a new user message to [session] without waiting for
  /// the assistant's reply. OpenCode server versions use different successful
  /// response codes, so every 2xx response is definitive acceptance.
  ///
  /// Never logs [text] or any part of the request/response.
  Future<void> sendPromptAsync(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String text, {
    List<QueuedAttachment> attachments = const <QueuedAttachment>[],
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/prompt_async?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'parts': [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          // OpenCode accepts file parts by URL; a `data:` URL carries the
          // bytes inline, which is how the official mobile client uploads.
          for (final attachment in attachments)
            {
              'type': 'file',
              'mime': attachment.mediaType,
              'filename': attachment.name,
              'url':
                  'data:${attachment.mediaType};base64,'
                  '${base64Encode(attachment.bytes)}',
            },
        ],
        if (executionOptions.hasModel)
          'model': {
            'providerID': executionOptions.modelProviderId,
            'modelID': executionOptions.modelId,
          },
        if (executionOptions.agentName != null)
          'agent': executionOptions.agentName,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
    }
  }

  /// Executes a slash command selected from OpenCode's command capability.
  Future<void> executeCommand(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
    String command,
    String arguments, {
    PromptExecutionOptions executionOptions = const PromptExecutionOptions(),
  }) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final response = await _transport.post(
      profile,
      password,
      '/session/${Uri.encodeComponent(session.id)}/command?$query',
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'command': command,
        'arguments': arguments,
        if (executionOptions.agentName != null)
          'agent': executionOptions.agentName,
        if (executionOptions.hasModel)
          'model': {
            'providerID': executionOptions.modelProviderId,
            'modelID': executionOptions.modelId,
          },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeHttpFailure(response.statusCode);
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

  /// Re-fetches human interactions that may have been emitted while the app
  /// was asleep or disconnected. OpenCode keeps permissions and questions in
  /// separate global lists, both scoped by the project directory.
  Future<List<PendingApproval>> listPendingApprovals(
    ServerProfile profile,
    String? password,
    OpenCodeSession session,
  ) async {
    final query = Uri(queryParameters: {'directory': session.directory}).query;
    final responses = await Future.wait([
      _get(profile, password, '/permission?$query'),
      _get(profile, password, '/question?$query'),
    ]);
    final permissions = jsonDecode(responses[0].body);
    final questions = jsonDecode(responses[1].body);
    if (permissions is! List || questions is! List) {
      throw const FormatException(
        'Pending permission and question responses must be lists.',
      );
    }
    return [
      ...permissions
          .whereType<Map<String, dynamic>>()
          .map((json) => mapPendingPermission(json, sessionId: session.id))
          .whereType<PendingApproval>(),
      ...questions
          .whereType<Map<String, dynamic>>()
          .map((json) => mapPendingQuestion(json, sessionId: session.id))
          .whereType<PendingApproval>(),
    ];
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

class OpenCodeTodoRecord {
  const OpenCodeTodoRecord({
    this.id,
    required this.content,
    required this.status,
    required this.priority,
  });

  factory OpenCodeTodoRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final content = json['content'];
    final status = json['status'];
    final priority = json['priority'];
    // OpenCode's `Todo` schema requires only content/status/priority; `id`
    // is not part of it, so it must stay optional here.
    if (content is! String || status is! String || priority is! String) {
      throw const FormatException('Todo has invalid required fields.');
    }
    return OpenCodeTodoRecord(
      id: id is String ? id : null,
      content: content,
      status: status,
      priority: priority,
    );
  }

  final String? id;
  final String content;
  final String status;
  final String priority;
}

class OpenCodeFileDiffRecord {
  const OpenCodeFileDiffRecord({
    required this.file,
    required this.patch,
    required this.additions,
    required this.deletions,
    this.status,
  });

  /// Maps OpenCode's `SnapshotFileDiff`, whose only required fields are
  /// `additions` and `deletions`. The unified `patch` and the file path are
  /// optional, so a diff for a renamed or binary file still parses.
  factory OpenCodeFileDiffRecord.fromJson(Map<String, dynamic> json) {
    final file = json['file'];
    final patch = json['patch'];
    final status = json['status'];
    final additions = json['additions'];
    final deletions = json['deletions'];
    if (additions is! num || deletions is! num) {
      throw const FormatException('File diff has invalid required fields.');
    }
    return OpenCodeFileDiffRecord(
      file: file is String ? file : '',
      patch: patch is String ? patch : '',
      additions: additions.toInt(),
      deletions: deletions.toInt(),
      status: status is String ? status : null,
    );
  }

  final String file;
  final String patch;
  final int additions;
  final int deletions;
  final String? status;
}

class OpenCodeMessageRecord {
  const OpenCodeMessageRecord({
    required this.id,
    required this.role,
    required this.createdAtMillis,
    required this.text,
    required this.details,
    this.error,
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
    final details = <OpenCodeMessageDetailRecord>[];
    for (final rawPart in parts.whereType<Map<String, dynamic>>()) {
      final id = rawPart['id'];
      final type = rawPart['type'];
      if (id is! String || type is! String) {
        continue;
      }
      if (type == 'reasoning' && rawPart['text'] is String) {
        details.add(
          OpenCodeReasoningRecord(id: id, text: rawPart['text'] as String),
        );
      } else if (type == 'tool') {
        final tool = rawPart['tool'];
        final state = rawPart['state'];
        if (tool is String && state is Map<String, dynamic>) {
          details.add(
            OpenCodeToolRecord(
              id: id,
              tool: tool,
              status: state['status'] is String
                  ? state['status'] as String
                  : 'pending',
              input: _boundedJson(state['input'], 1600),
              output: _boundedText(state['output'], 6000),
              error: _boundedText(state['error'], 2400),
            ),
          );
        }
      }
    }
    return OpenCodeMessageRecord(
      id: id,
      role: role,
      createdAtMillis: createdAt.toInt(),
      text: text,
      details: details,
      error: _messageError(info['error']),
    );
  }

  final String id;
  final String role;
  final int createdAtMillis;
  final String text;
  final List<OpenCodeMessageDetailRecord> details;
  final String? error;
}

sealed class OpenCodeMessageDetailRecord {
  const OpenCodeMessageDetailRecord({required this.id});

  final String id;
}

class OpenCodeReasoningRecord extends OpenCodeMessageDetailRecord {
  const OpenCodeReasoningRecord({required super.id, required this.text});

  final String text;
}

class OpenCodeToolRecord extends OpenCodeMessageDetailRecord {
  const OpenCodeToolRecord({
    required super.id,
    required this.tool,
    required this.status,
    this.input,
    this.output,
    this.error,
  });

  final String tool;
  final String status;
  final String? input;
  final String? output;
  final String? error;
}

String? _boundedJson(Object? value, int maxLength) {
  if (value == null) {
    return null;
  }
  try {
    return _truncate(jsonEncode(value), maxLength);
  } on JsonUnsupportedObjectError {
    return null;
  }
}

String? _boundedText(Object? value, int maxLength) {
  return value is String && value.isNotEmpty
      ? _truncate(value, maxLength)
      : null;
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}\n… output truncated';
}

String? _messageError(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is Map<String, dynamic>) {
    final data = value['data'];
    if (data is Map<String, dynamic> && data['message'] is String) {
      return data['message'] as String;
    }
    if (value['message'] is String) {
      return value['message'] as String;
    }
    if (value['name'] is String) {
      return value['name'] as String;
    }
  }
  return null;
}
