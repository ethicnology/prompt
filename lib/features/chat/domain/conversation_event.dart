/// Pure mapping from [OpenCodeEventEnvelope] to typed conversation events.
///
/// [mapConversationEvent] is a total function: it never throws and never
/// performs I/O or logging. Malformed payloads, events for another session
/// or directory, and event types this conversation does not model all map
/// to `null` and are ignored by the caller.
library;

import '../../../data/remote/opencode_event_service.dart';
import 'conversation_message.dart';
import 'session_block_reason.dart';
import 'session_execution_state.dart';

/// A conversation-scoped event, already validated and reduced from raw
/// OpenCode JSON. See `conversation_state.dart` for the reducer that folds
/// these into a [ConversationState].
sealed class ConversationEvent {
  const ConversationEvent();
}

/// A message was created or had its metadata (role, timing, ...) updated.
/// Carries no parts; existing parts for this message are preserved by the
/// reducer.
final class MessageUpdatedEvent extends ConversationEvent {
  const MessageUpdatedEvent({
    required this.sessionId,
    required this.messageId,
    required this.role,
  });

  final String sessionId;
  final String messageId;
  final ConversationRole role;
}

/// A message and all of its parts were removed.
final class MessageRemovedEvent extends ConversationEvent {
  const MessageRemovedEvent({required this.sessionId, required this.messageId});

  final String sessionId;
  final String messageId;
}

/// A full, authoritative snapshot of one message part.
final class MessagePartUpdatedEvent extends ConversationEvent {
  const MessagePartUpdatedEvent({required this.sessionId, required this.part});

  final String sessionId;
  final MessagePart part;
}

/// One part was removed from a message.
final class MessagePartRemovedEvent extends ConversationEvent {
  const MessagePartRemovedEvent({
    required this.sessionId,
    required this.messageId,
    required this.partId,
  });

  final String sessionId;
  final String messageId;
  final String partId;
}

/// The session's execution state changed to busy, idle, or retrying.
final class SessionStatusEvent extends ConversationEvent {
  const SessionStatusEvent({required this.sessionId, required this.state});

  final String sessionId;
  final SessionExecutionState state;
}

/// The session became idle. Distinct from a `session.status` event carrying
/// an idle state; the server emits both, and either is sufficient to settle
/// the session to idle.
final class SessionIdleEvent extends ConversationEvent {
  const SessionIdleEvent({required this.sessionId});

  final String sessionId;
}

/// A permission or question is pending for the session, reduced from
/// `permission.updated`. Carries only the session id and a coarse
/// [SessionBlockReason] — never the permission's id, title, pattern, or
/// metadata, which may describe a sensitive shell command, file path, or
/// question text. `permission.replied` is intentionally not modeled here:
/// resuming a blocked queue is only ever confirmed by an authoritative
/// `session.status`/`session.idle` event, never by the reply alone.
final class SessionBlockedEvent extends ConversationEvent {
  const SessionBlockedEvent({required this.sessionId, required this.reason});

  final String sessionId;
  final SessionBlockReason reason;
}

/// Maps [envelope] to a [ConversationEvent] scoped to [sessionId].
///
/// Events for a different session, a different [directory] (when
/// [directory] is provided and the envelope reports one), an unmodeled
/// OpenCode event type, or a malformed payload all yield `null`.
ConversationEvent? mapConversationEvent(
  OpenCodeEventEnvelope envelope, {
  required String sessionId,
  String? directory,
}) {
  if (directory != null &&
      envelope.directory != null &&
      envelope.directory != directory) {
    return null;
  }

  final properties = envelope.payload['properties'];
  if (properties is! Map<String, dynamic>) {
    return null;
  }

  switch (envelope.type) {
    case 'message.updated':
      return _mapMessageUpdated(properties, sessionId);
    case 'message.removed':
      return _mapMessageRemoved(properties, sessionId);
    case 'message.part.updated':
      return _mapMessagePartUpdated(properties, sessionId);
    case 'message.part.removed':
      return _mapMessagePartRemoved(properties, sessionId);
    case 'session.status':
      return _mapSessionStatus(properties, sessionId);
    case 'session.idle':
      return _mapSessionIdle(properties, sessionId);
    case 'permission.updated':
      return _mapPermissionUpdated(properties, sessionId);
    default:
      return null;
  }
}

ConversationEvent? _mapMessageUpdated(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final info = properties['info'];
  if (info is! Map<String, dynamic>) {
    return null;
  }
  final id = info['id'];
  final infoSessionId = info['sessionID'];
  final role = info['role'];
  if (id is! String || infoSessionId is! String || role is! String) {
    return null;
  }
  if (infoSessionId != sessionId) {
    return null;
  }
  final mappedRole = switch (role) {
    'user' => ConversationRole.user,
    'assistant' => ConversationRole.assistant,
    _ => null,
  };
  if (mappedRole == null) {
    return null;
  }
  return MessageUpdatedEvent(
    sessionId: infoSessionId,
    messageId: id,
    role: mappedRole,
  );
}

ConversationEvent? _mapMessageRemoved(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final messageId = properties['messageID'];
  if (eventSessionId is! String || messageId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  return MessageRemovedEvent(sessionId: eventSessionId, messageId: messageId);
}

ConversationEvent? _mapMessagePartUpdated(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final rawPart = properties['part'];
  if (rawPart is! Map<String, dynamic>) {
    return null;
  }
  final partSessionId = rawPart['sessionID'];
  if (partSessionId is! String || partSessionId != sessionId) {
    return null;
  }
  final part = _mapMessagePart(rawPart);
  if (part == null) {
    return null;
  }
  return MessagePartUpdatedEvent(sessionId: partSessionId, part: part);
}

MessagePart? _mapMessagePart(Map<String, dynamic> json) {
  final id = json['id'];
  final messageId = json['messageID'];
  final type = json['type'];
  if (id is! String || messageId is! String || type is! String) {
    return null;
  }
  switch (type) {
    case 'text':
      final text = json['text'];
      if (text is! String) {
        return null;
      }
      return TextMessagePart(id: id, messageId: messageId, text: text);
    case 'reasoning':
      final text = json['text'];
      if (text is! String) {
        return null;
      }
      return ReasoningMessagePart(id: id, messageId: messageId, text: text);
    case 'tool':
      final tool = json['tool'];
      final state = json['state'];
      if (tool is! String || state is! Map<String, dynamic>) {
        return null;
      }
      final status = _mapToolStatus(state['status']);
      if (status == null) {
        return null;
      }
      return ToolMessagePart(
        id: id,
        messageId: messageId,
        tool: tool,
        status: status,
      );
    default:
      return OtherMessagePart(id: id, messageId: messageId, partType: type);
  }
}

ToolPartStatus? _mapToolStatus(Object? status) {
  return switch (status) {
    'pending' => ToolPartStatus.pending,
    'running' => ToolPartStatus.running,
    'completed' => ToolPartStatus.completed,
    'error' => ToolPartStatus.error,
    _ => null,
  };
}

ConversationEvent? _mapMessagePartRemoved(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final messageId = properties['messageID'];
  final partId = properties['partID'];
  if (eventSessionId is! String || messageId is! String || partId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  return MessagePartRemovedEvent(
    sessionId: eventSessionId,
    messageId: messageId,
    partId: partId,
  );
}

ConversationEvent? _mapSessionStatus(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  final status = properties['status'];
  if (eventSessionId is! String || status is! Map<String, dynamic>) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  final state = _mapSessionExecutionState(status);
  if (state == null) {
    return null;
  }
  return SessionStatusEvent(sessionId: eventSessionId, state: state);
}

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

ConversationEvent? _mapSessionIdle(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  if (eventSessionId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  return SessionIdleEvent(sessionId: eventSessionId);
}

/// `permission.updated`'s `properties` is the OpenCode `Permission` object
/// itself (not a wrapper). Only `sessionID` and `type` are read; `title`,
/// `pattern`, `metadata`, and every other field may carry a sensitive
/// command, path, or question and must never enter this domain event.
ConversationEvent? _mapPermissionUpdated(
  Map<String, dynamic> properties,
  String sessionId,
) {
  final eventSessionId = properties['sessionID'];
  if (eventSessionId is! String) {
    return null;
  }
  if (eventSessionId != sessionId) {
    return null;
  }
  final type = properties['type'];
  final reason = type == 'question'
      ? SessionBlockReason.question
      : SessionBlockReason.permission;
  return SessionBlockedEvent(sessionId: eventSessionId, reason: reason);
}
