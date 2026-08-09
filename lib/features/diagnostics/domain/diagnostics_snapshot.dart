class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.isHealthy,
    required this.version,
    required this.mcp,
    required this.lsp,
    required this.formatters,
  });

  final bool isHealthy;
  final String version;
  final McpDiagnostics mcp;
  final LspDiagnostics lsp;
  final FormatterDiagnostics formatters;
}

class McpDiagnostics {
  const McpDiagnostics({
    required this.connected,
    required this.needsAttention,
    required this.disabled,
  });

  final int connected;
  final int needsAttention;
  final int disabled;

  int get total => connected + needsAttention + disabled;
}

class LspDiagnostics {
  const LspDiagnostics({required this.connected, required this.unavailable});

  final int connected;
  final int unavailable;

  int get total => connected + unavailable;
}

class FormatterDiagnostics {
  const FormatterDiagnostics({required this.enabled, required this.disabled});

  final int enabled;
  final int disabled;

  int get total => enabled + disabled;
}
