import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credentials_store.dart';

class SecureCredentialsService implements CredentialsStore {
  SecureCredentialsService([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _passwordKey = 'prompt.server.password';

  final FlutterSecureStorage _storage;

  @override
  Future<void> savePassword(String? password) {
    if (password == null || password.isEmpty) {
      return clearPassword();
    }
    return _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<String?> readPassword() {
    return _storage.read(key: _passwordKey);
  }

  @override
  Future<void> clearPassword() {
    return _storage.delete(key: _passwordKey);
  }
}
