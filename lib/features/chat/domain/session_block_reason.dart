/// Pure domain model of why a session's queue is currently blocked waiting
/// on a human decision, reduced from the OpenCode `permission.updated` SSE
/// event. Distinct from [SessionExecutionState][see session_execution_state
/// .dart]: a session can be busy or idle and still be blocked awaiting an
/// approval or a reply, since OpenCode reports these independently.
library;

/// Why a session is currently blocked. Carries no permission id, title,
/// pattern, or metadata: only the coarse reason, derived from the OpenCode
/// `Permission.type` field ("question" for the built-in `question`
/// permission, anything else for a tool-call approval).
enum SessionBlockReason {
  /// A tool call (`bash`, `edit`, `webfetch`, ...) is awaiting an
  /// allow/deny decision.
  permission,

  /// The agent used the `question` tool and is awaiting the user's reply.
  question,
}
