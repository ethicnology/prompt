enum QueueFailure {
  /// The prompt text was empty after trimming whitespace.
  emptyPromptText,

  /// No queued prompt exists with the given id.
  notFound,

  /// The requested change is not a valid transition from the prompt's
  /// current state (for example editing a prompt that is currently
  /// `sending`, or resuming a prompt that is not `paused`).
  invalidTransition,

  /// A reorder was rejected because a prompt in that session is currently
  /// `sending`, or because the supplied ids do not exactly match the
  /// session's reorderable prompts.
  invalidReorder,

  /// The local database could not complete the operation.
  storageUnavailable,
}

extension QueueFailureMessage on QueueFailure {
  String get message {
    return switch (this) {
      QueueFailure.emptyPromptText => 'Enter a prompt before queuing it.',
      QueueFailure.notFound => 'This queued prompt no longer exists.',
      QueueFailure.invalidTransition =>
        'This queued prompt cannot change state right now.',
      QueueFailure.invalidReorder =>
        'The queue order could not be updated right now.',
      QueueFailure.storageUnavailable =>
        'Prompt cannot reach its local database right now.',
    };
  }
}
