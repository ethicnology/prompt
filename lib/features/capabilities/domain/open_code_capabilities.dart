import 'open_code_agent.dart';
import 'open_code_model.dart';
import 'open_code_slash_command.dart';

class OpenCodeCapabilities {
  const OpenCodeCapabilities({
    required this.models,
    required this.agents,
    required this.commands,
  });

  final List<OpenCodeModel> models;
  final List<OpenCodeAgent> agents;
  final List<OpenCodeSlashCommand> commands;

  bool get isEmpty => models.isEmpty && agents.isEmpty && commands.isEmpty;
}
