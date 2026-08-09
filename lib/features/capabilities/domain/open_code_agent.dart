enum OpenCodeAgentMode { primary, subagent, all }

class OpenCodeAgent {
  const OpenCodeAgent({
    required this.name,
    required this.mode,
    required this.isBuiltIn,
    this.description,
  });

  final String name;
  final String? description;
  final OpenCodeAgentMode mode;
  final bool isBuiltIn;
}
