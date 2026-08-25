import 'dart:convert';

import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/remote_terminal.dart';

class OpenCodeTerminalService {
  OpenCodeTerminalService(this._transport);

  final OpenCodeTransport _transport;

  Future<List<RemoteTerminal>> list(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final response = await _transport.get(
      profile,
      password,
      _path('/pty', directory),
    );
    _requireSuccess(response.statusCode);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('PTY list is malformed.');
    return decoded.map<RemoteTerminal>(_terminal).toList(growable: false);
  }

  Future<RemoteTerminal> create(
    ServerProfile profile,
    String? password,
    String directory,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      _path('/pty', directory),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'cwd': directory}),
    );
    _requireSuccess(response.statusCode);
    return _terminal(jsonDecode(response.body));
  }

  Future<void> close(
    ServerProfile profile,
    String? password,
    String directory,
    String id,
  ) async {
    final response = await _transport.delete(
      profile,
      password,
      _path('/pty/$id', directory),
    );
    _requireSuccess(response.statusCode);
  }

  Future<String> connectTicket(
    ServerProfile profile,
    String? password,
    String directory,
    String id,
  ) async {
    final response = await _transport.post(
      profile,
      password,
      _path('/pty/$id/connectToken', directory),
    );
    _requireSuccess(response.statusCode);
    final headerTicket =
        response.headers['x-opencode-pty-ticket'] ??
        response.headers['x-opencode-ticket'] ??
        response.headers['ticket'];
    if (headerTicket != null && headerTicket.isNotEmpty) return headerTicket;
    final decoded = jsonDecode(response.body);
    final ticket = switch (decoded) {
      String value when value.isNotEmpty => value,
      {'ticket': String value} when value.isNotEmpty => value,
      {'token': String value} when value.isNotEmpty => value,
      _ => null,
    };
    if (ticket == null) throw const FormatException('PTY ticket is malformed.');
    return ticket;
  }

  String _path(String path, String directory) =>
      '$path?${Uri(queryParameters: {'directory': directory}).query}';

  void _requireSuccess(int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw OpenCodeHttpFailure(statusCode);
    }
  }

  RemoteTerminal _terminal(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        value['title'] is! String ||
        value['command'] is! String ||
        value['args'] is! List ||
        !(value['args'] as List).every((argument) => argument is String) ||
        value['cwd'] is! String ||
        value['status'] is! String ||
        value['pid'] is! num) {
      throw const FormatException('PTY is malformed.');
    }
    final status = value['status'] as String;
    if (status != 'running' && status != 'exited') {
      throw const FormatException('PTY is malformed.');
    }
    return RemoteTerminal(
      id: value['id'] as String,
      title: value['title'] as String,
      command: value['command'] as String,
      args: List.unmodifiable((value['args'] as List).cast<String>()),
      cwd: value['cwd'] as String,
      isRunning: status == 'running',
      pid: (value['pid'] as num).toInt(),
    );
  }
}
