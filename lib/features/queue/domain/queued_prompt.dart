import 'dart:typed_data';

import 'prompt_execution_options.dart';

/// A file that travels with a queued prompt.
///
/// The bytes are stored in Prompt's encrypted local database so a queued
/// prompt survives a restart exactly as its text does. [name] and [bytes]
/// must never be logged or exported.
class QueuedAttachment {
  const QueuedAttachment({
    required this.name,
    required this.mediaType,
    required this.bytes,
  });

  final String name;
  final String mediaType;
  final Uint8List bytes;

  @override
  String toString() => 'QueuedAttachment(bytes: ${bytes.lengthInBytes})';
}

/// A prompt's position in Prompt's durable, per-session send queue.
///
/// ```text
/// queued -> sending -> acknowledged
///   |          |
///   v          v
/// paused <---- failed
/// ```
///
/// `queued` moves to `paused` when a pending permission or question blocks
/// the session. `sending` moves to `acknowledged` once the server accepts
/// the prompt, or to `failed` otherwise. A `failed` prompt is paused for the
/// user to review; Prompt does not retry automatically. `paused` resumes to
/// `queued` only by explicit user action.
enum QueuedPromptState { queued, sending, paused, failed, acknowledged }

/// The OpenCode action serialized by a queue record.
enum QueuedOperationType { prompt, command }

enum QueuePauseReason {
  sessionGenerating,
  permissionPending,
  questionPending,
  networkUnavailable,
  sessionDeleted,
  submissionUnknown,
  serverRejected,
}

/// A durable, locally queued prompt for one OpenCode session.
///
/// [promptText] must never be logged, printed, or included in any
/// diagnostic export.
class QueuedPrompt {
  const QueuedPrompt({
    required this.id,
    required this.serverProfileId,
    required this.sessionId,
    required this.directory,
    required this.position,
    required this.promptText,
    this.operationType = QueuedOperationType.prompt,
    this.commandName,
    this.attachments = const <QueuedAttachment>[],
    required this.state,
    required this.attemptCount,
    required this.createdAt,
    required this.updatedAt,
    this.executionOptions = const PromptExecutionOptions(),
    this.pauseReason,
    this.sendingStartedAt,
    this.acknowledgedAt,
  });

  final String id;
  final String serverProfileId;
  final String sessionId;
  final String directory;
  final int position;
  final String promptText;
  final QueuedOperationType operationType;
  final String? commandName;

  /// Files submitted with this prompt, in selection order.
  final List<QueuedAttachment> attachments;
  final QueuedPromptState state;

  /// The reason the prompt is paused, or the reason the last send attempt
  /// failed while [state] is [QueuedPromptState.failed]. Never derived from
  /// or containing prompt text.
  final QueuePauseReason? pauseReason;
  final int attemptCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PromptExecutionOptions executionOptions;
  final DateTime? sendingStartedAt;
  final DateTime? acknowledgedAt;

  QueuedPrompt copyWith({
    int? position,
    String? promptText,
    QueuedPromptState? state,
    Object? pauseReason = _unset,
    int? attemptCount,
    DateTime? updatedAt,
    Object? sendingStartedAt = _unset,
    Object? acknowledgedAt = _unset,
  }) {
    return QueuedPrompt(
      id: id,
      serverProfileId: serverProfileId,
      sessionId: sessionId,
      directory: directory,
      position: position ?? this.position,
      promptText: promptText ?? this.promptText,
      operationType: operationType,
      commandName: commandName,
      attachments: attachments,
      state: state ?? this.state,
      pauseReason: pauseReason == _unset
          ? this.pauseReason
          : pauseReason as QueuePauseReason?,
      attemptCount: attemptCount ?? this.attemptCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      executionOptions: executionOptions,
      sendingStartedAt: sendingStartedAt == _unset
          ? this.sendingStartedAt
          : sendingStartedAt as DateTime?,
      acknowledgedAt: acknowledgedAt == _unset
          ? this.acknowledgedAt
          : acknowledgedAt as DateTime?,
    );
  }

  /// Deliberately excludes [promptText] from any representation used in
  /// logs, diagnostics, or crash reports.
  @override
  String toString() {
    return 'QueuedPrompt(id: $id, sessionId: $sessionId, position: $position, '
        'state: $state)';
  }
}

const Object _unset = Object();
