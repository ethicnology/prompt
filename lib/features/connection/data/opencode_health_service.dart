import '../../../data/remote/opencode_transport.dart';
import '../domain/server_profile.dart';

class OpenCodeHealthService {
  OpenCodeHealthService(this._transport);

  final OpenCodeTransport _transport;

  Future<int> checkHealth(ServerProfile profile, String? password) async {
    final response = await _transport.get(profile, password, '/global/health');
    return response.statusCode;
  }
}
