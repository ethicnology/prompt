class RemoteTerminal {
  const RemoteTerminal({
    required this.id,
    required this.title,
    required this.command,
    required this.args,
    required this.cwd,
    required this.isRunning,
    required this.pid,
  });

  final String id;
  final String title;
  final String command;
  final List<String> args;
  final String cwd;
  final bool isRunning;
  final int pid;
}

enum RemoteTerminalFailure {
  unavailable,
  unauthorized,
  unexpectedResponse,
  connectionFailed,
}

extension RemoteTerminalFailureMessage on RemoteTerminalFailure {
  String get message => switch (this) {
    RemoteTerminalFailure.unavailable =>
      'Remote terminal is unavailable on this experimental server.',
    RemoteTerminalFailure.unauthorized =>
      'The server rejected the saved credentials.',
    RemoteTerminalFailure.unexpectedResponse =>
      'The server returned an unsupported terminal response.',
    RemoteTerminalFailure.connectionFailed =>
      'The terminal connection could not be opened. Try again.',
  };
}
