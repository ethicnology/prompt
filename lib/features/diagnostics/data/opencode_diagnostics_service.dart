import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/remote/opencode_transport.dart';
import '../../connection/connection.dart';
import '../domain/diagnostics_snapshot.dart';

class OpenCodeDiagnosticsService {
  OpenCodeDiagnosticsService(this._transport);

  final OpenCodeTransport _transport;

  Future<DiagnosticsSnapshot> fetch(
    ServerProfile profile,
    String? password,
  ) async {
    final responses = await Future.wait([
      _get(profile, password, '/global/health'),
      _get(profile, password, '/mcp'),
      _get(profile, password, '/lsp'),
      _get(profile, password, '/formatter'),
    ]);
    final health = _health(responses[0].body);
    return DiagnosticsSnapshot(
      isHealthy: health.$1,
      version: health.$2,
      mcp: _mcp(responses[1].body),
      lsp: _lsp(responses[2].body),
      formatters: _formatters(responses[3].body),
    );
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

  (bool, String) _health(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic> ||
        value['healthy'] is! bool ||
        value['version'] is! String) {
      throw const FormatException('Health response is malformed.');
    }
    return (value['healthy'] as bool, value['version'] as String);
  }

  McpDiagnostics _mcp(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('MCP response is malformed.');
    }
    var connected = 0;
    var needsAttention = 0;
    var disabled = 0;
    for (final status in value.values) {
      if (status is! Map<String, dynamic> || status['status'] is! String) {
        throw const FormatException('MCP status is malformed.');
      }
      switch (status['status'] as String) {
        case 'connected':
          connected++;
        case 'disabled':
          disabled++;
        case 'failed' || 'needs_auth' || 'needs_client_registration':
          needsAttention++;
        default:
          throw const FormatException('MCP status is unsupported.');
      }
    }
    return McpDiagnostics(
      connected: connected,
      needsAttention: needsAttention,
      disabled: disabled,
    );
  }

  LspDiagnostics _lsp(String body) {
    final value = jsonDecode(body);
    if (value is! List) {
      throw const FormatException('LSP response is malformed.');
    }
    var connected = 0;
    var unavailable = 0;
    for (final status in value) {
      if (status is! Map<String, dynamic> || status['status'] is! String) {
        throw const FormatException('LSP status is malformed.');
      }
      switch (status['status'] as String) {
        case 'connected':
          connected++;
        case 'error':
          unavailable++;
        default:
          throw const FormatException('LSP status is unsupported.');
      }
    }
    return LspDiagnostics(connected: connected, unavailable: unavailable);
  }

  FormatterDiagnostics _formatters(String body) {
    final value = jsonDecode(body);
    if (value is! List) {
      throw const FormatException('Formatter response is malformed.');
    }
    var enabled = 0;
    for (final status in value) {
      if (status is! Map<String, dynamic> || status['enabled'] is! bool) {
        throw const FormatException('Formatter status is malformed.');
      }
      if (status['enabled'] as bool) {
        enabled++;
      }
    }
    return FormatterDiagnostics(
      enabled: enabled,
      disabled: value.length - enabled,
    );
  }
}
