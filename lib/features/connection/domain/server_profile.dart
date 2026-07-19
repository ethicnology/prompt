class ServerProfile {
  const ServerProfile({required this.origin, this.username});

  final Uri origin;
  final String? username;

  String get displayOrigin => origin.toString();
}
