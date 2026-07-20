import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credentials_store.dart';

class SecureCredentialsService implements CredentialsStore {
  SecureCredentialsService([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> savePassword(String profileId, String? password) {
    if (password == null || password.isEmpty) {
      return clearPassword(profileId);
    }
    return _storage.write(key: _passwordKey(profileId), value: password);
  }

  @override
  Future<String?> readPassword(String profileId) {
    return _storage.read(key: _passwordKey(profileId));
  }

  @override
  Future<void> clearPassword(String profileId) {
    return _storage.delete(key: _passwordKey(profileId));
  }

  String _passwordKey(String profileId) => 'prompt.server.$profileId.password';
}
