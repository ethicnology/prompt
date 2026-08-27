import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';

void main() {
  test('decodes SSE envelopes across arbitrary stream chunks', () async {
    final chunks = <List<int>>[
      utf8.encode('event: message\ndata: {"directory":"/workspace",'),
      utf8.encode('"payload":{"type":"session.status","sessionID":"s1",'),
      utf8.encode('"status":{"type":"busy"}}}\n\n: keepalive\n\n'),
      utf8.encode('data: {"directory":"/workspace","payload":'),
      utf8.encode('{"type":"session.idle","sessionID":"s1"}}\n\n'),
    ];

    final events = await OpenCodeEventService.decode(
      Stream.fromIterable(chunks),
    ).toList();

    expect(events, hasLength(2));
    expect(events.first.directory, '/workspace');
    expect(events.first.type, 'session.status');
    expect(events.first.payload['sessionID'], 's1');
    expect(events.last.type, 'session.idle');
  });

  test('ignores envelopes without an event payload', () async {
    final bytes = Stream.value(utf8.encode('data: {"directory":"/x"}\n\n'));

    final events = await OpenCodeEventService.decode(bytes).toList();

    expect(events, isEmpty);
  });

  test(
    'continues after malformed JSON and emits a subsequent valid event',
    () async {
      final bytes = Stream.value(
        utf8.encode(
          'data: {not valid JSON}\n\n'
          'data: {"directory":"/x","payload":{"type":"session.idle"}}\n\n',
        ),
      );

      final events = await OpenCodeEventService.decode(bytes).toList();

      expect(events, hasLength(1));
      expect(events.single.directory, '/x');
      expect(events.single.type, 'session.idle');
    },
  );

  test(
    'ignores a non-string directory but safely exposes a non-string type',
    () async {
      final bytes = Stream.value(
        utf8.encode(
          'data: {"directory":42,"payload":{"type":"ignored"}}\n\n'
          'data: {"directory":"/x","payload":{"type":42}}\n\n',
        ),
      );

      final events = await OpenCodeEventService.decode(bytes).toList();

      expect(events, hasLength(1));
      expect(events.single.directory, '/x');
      expect(events.single.type, isNull);
    },
  );
}
