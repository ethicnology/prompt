class OpenCodeSlashCommand {
  const OpenCodeSlashCommand({
    required this.name,
    required this.isSubtask,
    this.description,
    this.agentName,
    this.model,
  });

  final String name;
  final String? description;
  final String? agentName;
  final OpenCodeModelReference? model;
  final bool isSubtask;
}

class OpenCodeModelReference {
  const OpenCodeModelReference({
    required this.providerId,
    required this.modelId,
  });

  final String providerId;
  final String modelId;
}
