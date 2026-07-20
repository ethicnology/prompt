/// Failures specific to [QueueSendCoordinator.sendNow], distinct from
/// [QueueFailure] because they describe orchestration outcomes rather than
/// a single durable-queue state transition.
enum QueueSendNowFailure {
  /// `sendNow` was called with no session activated.
  noActiveSession,

  /// No queued prompt exists in the active session with the given id.
  promptNotFound,

  /// The prompt exists but is not currently `queued` (for example it is
  /// already `sending`, `paused`, `failed`, or `acknowledged`).
  promptNotQueued,

  /// The explicit `abort` request failed; Prompt never sends the chosen
  /// prompt without a definitive abort outcome.
  abortFailed,

  statusUnavailable,
}

extension QueueSendNowFailureMessage on QueueSendNowFailure {
  String get message {
    return switch (this) {
      QueueSendNowFailure.noActiveSession =>
        'Open a session before sending a prompt now.',
      QueueSendNowFailure.promptNotFound =>
        'This queued prompt no longer exists.',
      QueueSendNowFailure.promptNotQueued =>
        'Only a queued prompt can be sent now.',
      QueueSendNowFailure.abortFailed =>
        'Prompt could not cancel the current generation.',
      QueueSendNowFailure.statusUnavailable =>
        'Prompt could not confirm that the session stopped.',
    };
  }
}
