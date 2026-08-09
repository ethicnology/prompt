class OpenCodeModel {
  const OpenCodeModel({
    required this.providerId,
    required this.id,
    required this.name,
    required this.isProviderConnected,
  });

  final String providerId;
  final String id;
  final String name;
  final bool isProviderConnected;
}
