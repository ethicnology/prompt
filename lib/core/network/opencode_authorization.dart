import 'dart:convert';

Map<String, String> openCodeAuthorizationHeaders({
  required String? username,
  required String? password,
}) {
  if (username == null || username.isEmpty || password == null) {
    return const {};
  }

  final credentials = base64Encode(utf8.encode('$username:$password'));
  return {'authorization': 'Basic $credentials'};
}
