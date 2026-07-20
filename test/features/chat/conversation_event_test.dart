import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/data/remote/opencode_event_service.dart';
import 'package:prompt/features/chat/domain/conversation_event.dart';
import 'package:prompt/features/chat/domain/conversation_message.dart';
import 'package:prompt/features/chat/domain/session_execution_state.dart';

OpenCodeEventEnvelope _envelope(
  String type,
  Map<String, dynamic> properties, {
  String? directory,
}) {
  return OpenCodeEventEnvelope(
    directory: directory,
    payload: {'type': type, 'properties': properties},
  );
}

void main() {
  const sessionId = 'ses_1';

  group('message.updated', () {
    test('maps a user message for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': sessionId, 'role': 'user'},
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessageUpdatedEvent>());
      final updated = event as MessageUpdatedEvent;
      expect(updated.messageId, 'msg_1');
      expect(updated.sessionId, sessionId);
      expect(updated.role, ConversationRole.user);
    });

    test('maps an assistant message', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_2', 'sessionID': sessionId, 'role': 'assistant'},
        }),
        sessionId: sessionId,
      );

      expect((event as MessageUpdatedEvent).role, ConversationRole.assistant);
    });

    test('ignores messages belonging to another session', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': 'ses_other', 'role': 'user'},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores an unrecognized role', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {
          'info': {'id': 'msg_1', 'sessionID': sessionId, 'role': 'system'},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a malformed payload without throwing', () {
      final event = mapConversationEvent(
        _envelope('message.updated', {'info': 'not-a-map'}),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('message.removed', () {
    test('maps a removal for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('message.removed', {
          'sessionID': sessionId,
          'messageID': 'msg_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessageRemovedEvent>());
      expect((event as MessageRemovedEvent).messageId, 'msg_1');
    });

    test('ignores a removal for another session', () {
      final event = mapConversationEvent(
        _envelope('message.removed', {
          'sessionID': 'ses_other',
          'messageID': 'msg_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('message.part.updated', () {
    test('maps a text part', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_1',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'text',
            'text': 'Hello there',
          },
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessagePartUpdatedEvent>());
      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<TextMessagePart>());
      expect((part as TextMessagePart).text, 'Hello there');
      expect(part.id, 'part_1');
      expect(part.messageId, 'msg_1');
    });

    test('maps a reasoning part', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_2',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'reasoning',
            'text': 'thinking...',
          },
        }),
        sessionId: sessionId,
      );

      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<ReasoningMessagePart>());
      expect((part as ReasoningMessagePart).text, 'thinking...');
    });

    test('maps a tool part as a placeholder with status only', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_3',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'tool',
            'tool': 'bash',
            'callID': 'call_1',
            'state': {
              'status': 'running',
              'input': {'command': 'ls'},
            },
          },
        }),
        sessionId: sessionId,
      );

      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<ToolMessagePart>());
      final tool = part as ToolMessagePart;
      expect(tool.tool, 'bash');
      expect(tool.status, ToolPartStatus.running);
    });

    test('maps every documented tool status', () {
      for (final entry in const {
        'pending': ToolPartStatus.pending,
        'running': ToolPartStatus.running,
        'completed': ToolPartStatus.completed,
        'error': ToolPartStatus.error,
      }.entries) {
        final event = mapConversationEvent(
          _envelope('message.part.updated', {
            'part': {
              'id': 'part_x',
              'sessionID': sessionId,
              'messageID': 'msg_1',
              'type': 'tool',
              'tool': 'bash',
              'state': {'status': entry.key},
            },
          }),
          sessionId: sessionId,
        );

        final part = (event as MessagePartUpdatedEvent).part as ToolMessagePart;
        expect(part.status, entry.value);
      }
    });

    test('preserves identity of an unmodeled part type', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_4',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'step-start',
          },
        }),
        sessionId: sessionId,
      );

      final part = (event as MessagePartUpdatedEvent).part;
      expect(part, isA<OtherMessagePart>());
      expect((part as OtherMessagePart).partType, 'step-start');
    });

    test('ignores a part belonging to another session', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_1',
            'sessionID': 'ses_other',
            'messageID': 'msg_1',
            'type': 'text',
            'text': 'hi',
          },
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores a tool part with an unrecognized status', () {
      final event = mapConversationEvent(
        _envelope('message.part.updated', {
          'part': {
            'id': 'part_3',
            'sessionID': sessionId,
            'messageID': 'msg_1',
            'type': 'tool',
            'tool': 'bash',
            'state': {'status': 'unknown-status'},
          },
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('message.part.removed', () {
    test('maps a removal for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('message.part.removed', {
          'sessionID': sessionId,
          'messageID': 'msg_1',
          'partID': 'part_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isA<MessagePartRemovedEvent>());
      final removed = event as MessagePartRemovedEvent;
      expect(removed.messageId, 'msg_1');
      expect(removed.partId, 'part_1');
    });

    test('ignores a removal for another session', () {
      final event = mapConversationEvent(
        _envelope('message.part.removed', {
          'sessionID': 'ses_other',
          'messageID': 'msg_1',
          'partID': 'part_1',
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('session.status', () {
    test('maps a busy status', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {'type': 'busy'},
        }),
        sessionId: sessionId,
      );

      expect(event, isA<SessionStatusEvent>());
      expect((event as SessionStatusEvent).state, isA<SessionBusy>());
    });

    test('maps an idle status', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {'type': 'idle'},
        }),
        sessionId: sessionId,
      );

      expect((event as SessionStatusEvent).state, isA<SessionIdle>());
    });

    test('maps a retry status with attempt metadata', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': sessionId,
          'status': {
            'type': 'retry',
            'attempt': 2,
            'message': 'rate limited',
            'next': 1700000000000,
          },
        }),
        sessionId: sessionId,
      );

      final state = (event as SessionStatusEvent).state as SessionRetrying;
      expect(state.attempt, 2);
      expect(state.nextAttemptAtMillis, 1700000000000);
    });

    test('ignores a status for another session', () {
      final event = mapConversationEvent(
        _envelope('session.status', {
          'sessionID': 'ses_other',
          'status': {'type': 'busy'},
        }),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('session.idle', () {
    test('maps an idle event for the tracked session', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {'sessionID': sessionId}),
        sessionId: sessionId,
      );

      expect(event, isA<SessionIdleEvent>());
      expect((event as SessionIdleEvent).sessionId, sessionId);
    });

    test('ignores an idle event for another session', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {'sessionID': 'ses_other'}),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });
  });

  group('unrelated and unknown events', () {
    test('ignores unmodeled event types', () {
      for (final type in const [
        'session.error',
        'session.compacted',
        'file.edited',
        'permission.updated',
        'permission.replied',
        'installation.updated',
        'todo.updated',
        'server.connected',
        'server.instance.disposed',
        'lsp.updated',
        'something.unexpected',
      ]) {
        final event = mapConversationEvent(
          _envelope(type, {'sessionID': sessionId}),
          sessionId: sessionId,
        );

        expect(event, isNull, reason: 'expected $type to be ignored');
      }
    });

    test('ignores events carrying no type', () {
      final event = mapConversationEvent(
        OpenCodeEventEnvelope(directory: null, payload: {'properties': {}}),
        sessionId: sessionId,
      );

      expect(event, isNull);
    });

    test('ignores events for a different directory', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {
          'sessionID': sessionId,
        }, directory: '/workspace/other'),
        sessionId: sessionId,
        directory: '/workspace/mine',
      );

      expect(event, isNull);
    });

    test('accepts a matching directory', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {
          'sessionID': sessionId,
        }, directory: '/workspace/mine'),
        sessionId: sessionId,
        directory: '/workspace/mine',
      );

      expect(event, isA<SessionIdleEvent>());
    });

    test('accepts an event without a directory when one is required', () {
      final event = mapConversationEvent(
        _envelope('session.idle', {'sessionID': sessionId}),
        sessionId: sessionId,
        directory: '/workspace/mine',
      );

      expect(event, isA<SessionIdleEvent>());
    });
  });
}
