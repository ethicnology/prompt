/// Failures specific to [QueueSendCoordinator.respondToPermission],
/// [QueueSendCoordinator.replyToQuestion], and
/// [QueueSendCoordinator.rejectQuestion] — distinct from [QueueFailure]
/// because they describe an OpenCode approval round trip, not a durable
/// queue-row transition.
enum QueueApprovalFailure {
  /// The call was made with no session activated.
  noActiveSession,

  /// OpenCode rejected the request, or it could not be reached. Never
  /// carries the server's raw response detail.
  requestFailed,
}

extension QueueApprovalFailureMessage on QueueApprovalFailure {
  String get message {
    return switch (this) {
      QueueApprovalFailure.noActiveSession =>
        'Open a session before responding to a pending approval.',
      QueueApprovalFailure.requestFailed =>
        'Prompt could not send that response to the server. Try again.',
    };
  }
}
