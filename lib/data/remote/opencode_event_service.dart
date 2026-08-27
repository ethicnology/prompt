import 'dart:async';
import 'dart:convert';

import '../../features/connection/connection.dart';
import 'opencode_transport.dart';

class OpenCodeEventEnvelope {
  const OpenCodeEventEnvelope({required this.directory, required this.payload});

  final String? directory;
  final Map<String, dynamic> payload;

  String? get type {
    final value = payload['type'];
    return value is String ? value : null;
  }
}

class OpenCodeEventService {
  OpenCodeEventService(this._transport);

  final OpenCodeTransport _transport;

  Stream<OpenCodeEventEnvelope> connect(
    ServerProfile profile,
    String? password,
  ) async* {
    final response = await _transport.send(
      profile,
      password,
      '/global/event',
      headers: const {'accept': 'text/event-stream'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenCodeTransportFailure(response.statusCode);
    }
    yield* decode(response.stream);
  }

  static Stream<OpenCodeEventEnvelope> decode(Stream<List<int>> bytes) async* {
    final dataLines = <String>[];

    Future<OpenCodeEventEnvelope?> flush() async {
      if (dataLines.isEmpty) {
        return null;
      }
      final jsonText = dataLines.join('\n');
      dataLines.clear();
      try {
        final decoded = jsonDecode(jsonText);
        if (decoded is! Map<String, dynamic>) {
          return null;
        }
        final directory = decoded['directory'];
        if (directory != null && directory is! String) {
          return null;
        }
        final payload = decoded['payload'];
        if (payload is! Map<String, dynamic>) {
          return null;
        }
        return OpenCodeEventEnvelope(
          directory: directory as String?,
          payload: payload,
        );
      } on FormatException {
        return null;
      }
    }

    await for (final line
        in utf8.decoder.bind(bytes).transform(const LineSplitter())) {
      if (line.isEmpty) {
        final event = await flush();
        if (event != null) {
          yield event;
        }
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    final event = await flush();
    if (event != null) {
      yield event;
    }
  }
}
