import 'dart:async';
import 'dart:math';

import '../../../core/async/result.dart';
import '../../../data/local/prompt_database.dart' as db;
import '../../connection/domain/server_profile.dart';
import '../../sessions/domain/open_code_session.dart';
import '../domain/queue_failure.dart';
import '../domain/queued_prompt.dart';
import 'queue_prompts_dao.dart';

/// The durable, per-session source of truth for Prompt's local send queue.
///
/// This repository owns Drift access and typed state transitions only. It
/// never calls the OpenCode REST or SSE transport and never retries a send
/// automatically; deciding when to dispatch a queued prompt, and what to do
/// after a failure, is an orchestration concern outside this layer.
class QueuePromptsRepository {
  QueuePromptsRepository(this._dao, {String Function()? idGenerator})
    : _idGenerator = idGenerator ?? _randomId;

  final QueuePromptsDao _dao;
  final String Function() _idGenerator;

  /// Adds [promptText] to the end of [session]'s queue for [profile].
  ///
  /// Never interrupts an active generation; the caller decides when a
  /// queued prompt is dispatched.
  Future<Result<QueuedPrompt, QueueFailure>> enqueue({
    required ServerProfile profile,
    required OpenCodeSession session,
    required String promptText,
  }) async {
    final trimmed = promptText.trim();
    if (trimmed.isEmpty) {
      return const Err(QueueFailure.emptyPromptText);
    }
    return _run(() async {
      final row = await _dao.enqueue(
        id: _idGenerator(),
        serverProfileId: profile.id,
        sessionId: session.id,
        directory: session.directory,
        promptText: trimmed,
        now: DateTime.now(),
      );
      return _toDomain(row);
    });
  }

  /// Replaces the text of a prompt that is still `queued` or `paused`.
  Future<Result<QueuedPrompt, QueueFailure>> edit({
    required String promptId,
    required String promptText,
  }) async {
    final trimmed = promptText.trim();
    if (trimmed.isEmpty) {
      return const Err(QueueFailure.emptyPromptText);
    }
    return _run(() async {
      final row = await _dao.editText(
        id: promptId,
        promptText: trimmed,
        now: DateTime.now(),
      );
      return _toDomain(row);
    });
  }

  /// Removes a queued prompt. Rejected while the prompt is `sending`.
  Future<Result<QueuedPrompt, QueueFailure>> remove(String promptId) async {
    return _run(() async {
      final row = await _dao.remove(promptId);
      return _toDomain(row);
    });
  }

  /// Emits the ordered queue for [session] on [profile] whenever it
  /// changes, including prompts that are `sending`, `paused`, `failed`, or
  /// `acknowledged`.
  Stream<List<QueuedPrompt>> watchQueue({
    required ServerProfile profile,
    required OpenCodeSession session,
  }) {
    return _dao
        .watchQueue(serverProfileId: profile.id, sessionId: session.id)
        .map((rows) => rows.map(_toDomain).toList(growable: false));
  }

  /// Reassigns the order of a session's `queued`, `paused`, and `failed`
  /// prompts to [orderedPromptIds]. [orderedPromptIds] must be exactly the
  /// set of that session's reorderable prompt ids, and no prompt in the
  /// session may currently be `sending`.
  Future<Result<List<QueuedPrompt>, QueueFailure>> reorder({
    required ServerProfile profile,
    required OpenCodeSession session,
    required List<String> orderedPromptIds,
  }) async {
    return _run(() async {
      final rows = await _dao.reorder(
        serverProfileId: profile.id,
        sessionId: session.id,
        orderedIds: orderedPromptIds,
      );
      return rows.map(_toDomain).toList(growable: false);
    });
  }

  /// Marks a `queued` prompt as `sending`, recording another send attempt.
  Future<Result<QueuedPrompt, QueueFailure>> markSending(
    String promptId,
  ) async {
    return _run(() async {
      final row = await _dao.markSending(promptId, now: DateTime.now());
      return _toDomain(row);
    });
  }

  /// Marks a `sending` prompt as `acknowledged` by the server.
  Future<Result<QueuedPrompt, QueueFailure>> markAcknowledged(
    String promptId,
  ) async {
    return _run(() async {
      final row = await _dao.markAcknowledged(promptId, now: DateTime.now());
      return _toDomain(row);
    });
  }

  /// Marks a `sending` prompt as `failed`. Prompt does not retry
  /// automatically; a human decides whether to pause, edit, or remove it.
  Future<Result<QueuedPrompt, QueueFailure>> markFailed(
    String promptId, {
    QueuePauseReason reason = QueuePauseReason.serverRejected,
  }) async {
    return _run(() async {
      final row = await _dao.markFailed(
        promptId,
        reason: reason.name,
        now: DateTime.now(),
      );
      return _toDomain(row);
    });
  }

  /// Pauses a `queued` or `failed` prompt with an explicit [reason], such
  /// as a pending permission or question blocking the session.
  Future<Result<QueuedPrompt, QueueFailure>> markPaused(
    String promptId, {
    required QueuePauseReason reason,
  }) async {
    return _run(() async {
      final row = await _dao.markPaused(
        promptId,
        reason: reason.name,
        now: DateTime.now(),
      );
      return _toDomain(row);
    });
  }

  /// Resumes a `paused` prompt back to `queued`, keeping its position.
  Future<Result<QueuedPrompt, QueueFailure>> markQueued(String promptId) async {
    return _run(() async {
      final row = await _dao.markQueued(promptId, now: DateTime.now());
      return _toDomain(row);
    });
  }

  Future<Result<T, QueueFailure>> _run<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return Ok(await operation());
    } on QueuedPromptNotFound {
      return const Err(QueueFailure.notFound);
    } on InvalidQueuedPromptTransition {
      return const Err(QueueFailure.invalidTransition);
    } on InvalidQueueReorder {
      return const Err(QueueFailure.invalidReorder);
    } on Exception {
      return const Err(QueueFailure.storageUnavailable);
    }
  }

  QueuedPrompt _toDomain(db.QueuedPrompt row) {
    return QueuedPrompt(
      id: row.id,
      serverProfileId: row.serverProfileId,
      sessionId: row.sessionId,
      directory: row.directory,
      position: row.position,
      promptText: row.promptText,
      state: QueuedPromptState.values.byName(row.state),
      pauseReason: row.pauseReason == null
          ? null
          : QueuePauseReason.values.byName(row.pauseReason!),
      attemptCount: row.attemptCount,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAtMillis),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAtMillis),
      sendingStartedAt: row.sendingStartedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.sendingStartedAtMillis!),
      acknowledgedAt: row.acknowledgedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.acknowledgedAtMillis!),
    );
  }
}

String _randomId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
