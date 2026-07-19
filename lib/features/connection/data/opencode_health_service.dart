import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/server_profile.dart';

class OpenCodeHealthService {
  OpenCodeHealthService(this._client);

  final http.Client _client;

  Future<int> checkHealth(ServerProfile profile, String? password) async {
    final headers = <String, String>{};
    final username = profile.username;
    if (username != null && username.isNotEmpty && password != null) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      headers['authorization'] = 'Basic $credentials';
    }

    final response = await _client
        .get(profile.origin.resolve('/global/health'), headers: headers)
        .timeout(const Duration(seconds: 10));
    return response.statusCode;
  }
}
