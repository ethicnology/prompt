import 'package:http/http.dart' as http;

import '../../../core/network/opencode_authorization.dart';
import '../domain/server_profile.dart';

class OpenCodeHealthService {
  OpenCodeHealthService(this._client);

  final http.Client _client;

  Future<int> checkHealth(ServerProfile profile, String? password) async {
    final response = await _client
        .get(
          profile.origin.resolve('/global/health'),
          headers: openCodeAuthorizationHeaders(
            username: profile.username,
            password: password,
          ),
        )
        .timeout(const Duration(seconds: 10));
    return response.statusCode;
  }
}
