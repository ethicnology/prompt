import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/remote/opencode_session_status_parser.dart';

void main() {
  test('parses the same REST and SSE status fixtures', () {
    final fixtures = <Object?>[
      {'type': 'busy'},
      {'type': 'idle'},
      {'type': 'retry', 'attempt': 3, 'message': 'rate limited', 'next': 42},
      {'type': 'future'},
      {'type': 'retry', 'attempt': 'three'},
      const <Object?>[],
    ];

    for (final fixture in fixtures) {
      final rest = parseOpenCodeSessionStatus(fixture);
      final sse = parseOpenCodeSessionStatus(fixture);
      expect(rest.runtimeType, sse.runtimeType);
    }

    final retry = parseOpenCodeSessionStatus(fixtures[2]);
    expect(retry, isA<OpenCodeSessionStatusRetry>());
    expect((retry as OpenCodeSessionStatusRetry).message, 'rate limited');
  });

  test('returns typed unknown for malformed values without throwing', () {
    for (final value in <Object?>[
      null,
      'busy',
      [],
      {'type': 'retry'},
    ]) {
      expect(
        parseOpenCodeSessionStatus(value),
        isA<OpenCodeSessionStatusUnknown>(),
      );
    }
  });

  test('extracts official global session status and idle envelopes', () {
    final busy = parseOpenCodeGlobalSessionStatus({
      'type': 'session.status',
      'properties': {
        'sessionID': 'session-1',
        'status': {'type': 'busy'},
      },
    });
    expect(busy?.sessionId, 'session-1');
    expect(busy?.status, isA<OpenCodeSessionStatusBusy>());

    final retry = parseOpenCodeGlobalSessionStatus({
      'type': 'session.status',
      'properties': {
        'sessionID': 'session-2',
        'status': {'type': 'retry', 'attempt': 2, 'message': 'wait', 'next': 7},
      },
    });
    expect(retry?.status, isA<OpenCodeSessionStatusRetry>());

    final idle = parseOpenCodeGlobalSessionStatus({
      'type': 'session.idle',
      'properties': {'sessionID': 'session-3'},
    });
    expect(idle?.status, isA<OpenCodeSessionStatusIdle>());
  });

  test('ignores malformed and unknown global envelopes', () {
    for (final payload in <Map<String, dynamic>>[
      const {},
      {'type': 'session.status', 'properties': {}},
      {
        'type': 'session.status',
        'properties': {
          'sessionID': 'session-1',
          'status': {'type': 'future'},
        },
      },
      {
        'type': 'other.event',
        'properties': {'sessionID': 'session-1'},
      },
    ]) {
      expect(parseOpenCodeGlobalSessionStatus(payload), isNull);
    }
  });
}
