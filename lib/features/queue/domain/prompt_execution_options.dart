/// Optional OpenCode execution choices captured when a prompt is queued.
///
/// A model selection is always a provider/model pair because OpenCode's API
/// requires both identifiers. Either a model or an agent may be selected
/// independently.
class PromptExecutionOptions {
  const PromptExecutionOptions({
    this.modelProviderId,
    this.modelId,
    this.agentName,
  }) : assert(
         (modelProviderId == null) == (modelId == null),
         'A model selection needs both provider and model ids.',
       );

  final String? modelProviderId;
  final String? modelId;
  final String? agentName;

  bool get hasModel => modelProviderId != null;

  bool get isEmpty => !hasModel && agentName == null;
}
