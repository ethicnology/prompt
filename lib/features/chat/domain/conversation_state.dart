/// Pure reducer that folds [ConversationEvent]s, already mapped by
/// `conversation_event.dart`, into a [ConversationState]. This file performs
/// no I/O, no logging, and no OpenCode/HTTP/Drift access; it is safe to unit
/// test with plain Dart values.
library;

import 'conversation_event.dart';
import 'conversation_message.dart';
import 'session_execution_state.dart';

/// Immutable snapshot of a live conversation: its messages, in first-seen
/// order, and the execution state of every session referenced so far.
class ConversationState {
  const ConversationState({
    this.messages = const <String, ConversationMessage>{},
    this.sessionStates = const <String, SessionExecutionState>{},
  });

  /// Messages keyed by message id, preserving the order in which each
  /// message was first observed.
  final Map<String, ConversationMessage> messages;

  /// Execution state keyed by session id.
  final Map<String, SessionExecutionState> sessionStates;

  /// Messages in first-seen order.
  List<ConversationMessage> get orderedMessages =>
      List.unmodifiable(messages.values);

  ConversationState copyWith({
    Map<String, ConversationMessage>? messages,
    Map<String, SessionExecutionState>? sessionStates,
  }) {
    return ConversationState(
      messages: messages ?? this.messages,
      sessionStates: sessionStates ?? this.sessionStates,
    );
  }
}

/// Folds [event] onto [state] and returns the resulting state. [state] is
/// never mutated in place.
ConversationState reduceConversationEvent(
  ConversationState state,
  ConversationEvent event,
) {
  switch (event) {
    case MessageUpdatedEvent():
      return _reduceMessageUpdated(state, event);
    case MessageRemovedEvent():
      return _reduceMessageRemoved(state, event);
    case MessagePartUpdatedEvent():
      return _reduceMessagePartUpdated(state, event);
    case MessagePartRemovedEvent():
      return _reduceMessagePartRemoved(state, event);
    case SessionStatusEvent():
      return _reduceSessionStatus(state, event);
    case SessionIdleEvent():
      return _reduceSessionIdle(state, event);
  }
}

ConversationState _reduceMessageUpdated(
  ConversationState state,
  MessageUpdatedEvent event,
) {
  final existing = state.messages[event.messageId];
  final messages = Map<String, ConversationMessage>.of(state.messages);
  messages[event.messageId] = ConversationMessage(
    id: event.messageId,
    sessionId: event.sessionId,
    role: event.role,
    parts: existing?.parts ?? const <MessagePart>[],
  );
  return state.copyWith(messages: messages);
}

ConversationState _reduceMessageRemoved(
  ConversationState state,
  MessageRemovedEvent event,
) {
  if (!state.messages.containsKey(event.messageId)) {
    return state;
  }
  final messages = Map<String, ConversationMessage>.of(state.messages)
    ..remove(event.messageId);
  return state.copyWith(messages: messages);
}

ConversationState _reduceMessagePartUpdated(
  ConversationState state,
  MessagePartUpdatedEvent event,
) {
  final part = event.part;
  final existing = state.messages[part.messageId];
  final base =
      existing ??
      ConversationMessage(
        id: part.messageId,
        sessionId: event.sessionId,
        role: ConversationRole.unknown,
      );
  final messages = Map<String, ConversationMessage>.of(state.messages);
  messages[part.messageId] = base.copyWith(
    parts: _upsertPart(base.parts, part),
  );
  return state.copyWith(messages: messages);
}

List<MessagePart> _upsertPart(List<MessagePart> parts, MessagePart part) {
  final index = parts.indexWhere((existing) => existing.id == part.id);
  if (index == -1) {
    return List<MessagePart>.of(parts)..add(part);
  }
  final next = List<MessagePart>.of(parts);
  next[index] = part;
  return next;
}

ConversationState _reduceMessagePartRemoved(
  ConversationState state,
  MessagePartRemovedEvent event,
) {
  final existing = state.messages[event.messageId];
  if (existing == null) {
    return state;
  }
  final parts = existing.parts
      .where((part) => part.id != event.partId)
      .toList(growable: false);
  if (parts.length == existing.parts.length) {
    return state;
  }
  final messages = Map<String, ConversationMessage>.of(state.messages);
  messages[event.messageId] = existing.copyWith(parts: parts);
  return state.copyWith(messages: messages);
}

ConversationState _reduceSessionStatus(
  ConversationState state,
  SessionStatusEvent event,
) {
  final sessionStates = Map<String, SessionExecutionState>.of(
    state.sessionStates,
  );
  sessionStates[event.sessionId] = event.state;
  return state.copyWith(sessionStates: sessionStates);
}

ConversationState _reduceSessionIdle(
  ConversationState state,
  SessionIdleEvent event,
) {
  final sessionStates = Map<String, SessionExecutionState>.of(
    state.sessionStates,
  );
  sessionStates[event.sessionId] = const SessionIdle();
  return state.copyWith(sessionStates: sessionStates);
}
