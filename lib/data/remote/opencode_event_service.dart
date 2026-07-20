import 'dart:async';
import 'dart:convert';

import '../../features/connection/domain/server_profile.dart';
import 'opencode_transport.dart';

class OpenCodeEventEnvelope {
  const OpenCodeEventEnvelope({required this.directory, required this.payload});

  final String? directory;
  final Map<String, dynamic> payload;

  String? get type => payload['type'] as String?;
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
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final payload = decoded['payload'];
      if (payload is! Map<String, dynamic>) {
        return null;
      }
      return OpenCodeEventEnvelope(
        directory: decoded['directory'] as String?,
        payload: payload,
      );
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
