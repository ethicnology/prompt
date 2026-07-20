import 'package:http/http.dart' as http;

import '../../core/network/connection_origin_policy.dart';
import '../../core/network/opencode_authorization.dart';
import '../../features/connection/domain/server_profile.dart';

class InvalidOpenCodeOrigin implements Exception {
  const InvalidOpenCodeOrigin();
}

class OpenCodeTransportFailure implements Exception {
  const OpenCodeTransportFailure(this.statusCode);

  final int statusCode;
}

class OpenCodeHttpFailure implements Exception {
  const OpenCodeHttpFailure(this.statusCode);

  final int statusCode;
}

class OpenCodeTransport {
  OpenCodeTransport(this._client);

  final http.Client _client;

  Future<http.Response> get(
    ServerProfile profile,
    String? password,
    String path,
  ) {
    return _client
        .get(_uri(profile, path), headers: _headers(profile, password))
        .timeout(const Duration(seconds: 15));
  }

  Future<http.Response> post(
    ServerProfile profile,
    String? password,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) {
    return _client
        .post(
          _uri(profile, path),
          headers: {..._headers(profile, password), ...?headers},
          body: body,
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<http.StreamedResponse> send(
    ServerProfile profile,
    String? password,
    String path, {
    Map<String, String>? headers,
  }) {
    final request = http.Request('GET', _uri(profile, path));
    request.headers.addAll({..._headers(profile, password), ...?headers});
    return _client.send(request).timeout(const Duration(seconds: 15));
  }

  Uri _uri(ServerProfile profile, String path) {
    if (!ConnectionOriginPolicy.supports(profile.origin)) {
      throw const InvalidOpenCodeOrigin();
    }
    return profile.origin.resolve(path);
  }

  Map<String, String> _headers(ServerProfile profile, String? password) {
    return openCodeAuthorizationHeaders(
      username: profile.username,
      password: password,
    );
  }
}
