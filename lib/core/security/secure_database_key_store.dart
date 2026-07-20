import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'database_key_store.dart';

/// Creates or reuses a random 32-byte local database encryption key in the
/// platform secure storage (Android Keystore, Linux libsecret).
///
/// The key is generated once, the first time [loadOrCreateKey] is called
/// with nothing yet stored, and is then reused for as long as the secure
/// storage entry survives. Nothing here ever logs, prints, or includes the
/// key value in an exception; only [DatabaseKeyStoreUnavailable] (wrapping
/// the platform's own read/write exception) crosses this class's public
/// boundary on failure.
class SecureDatabaseKeyStore implements DatabaseKeyStore {
  SecureDatabaseKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  /// Exposed for tests that need to assert against the exact storage key
  /// name without duplicating the literal.
  static const storageKey = 'prompt.database.encryptionKey';

  static const _keyLengthBytes = 32;

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List> loadOrCreateKey() async {
    try {
      final stored = await _storage.read(key: storageKey);
      final decoded = stored == null ? null : _decode(stored);
      if (decoded != null) {
        return decoded;
      }
      final generated = _generate();
      await _storage.write(key: storageKey, value: base64Encode(generated));
      return generated;
    } on Exception catch (cause) {
      throw DatabaseKeyStoreUnavailable(cause);
    }
  }

  Uint8List _generate() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_keyLengthBytes, (_) => random.nextInt(256)),
    );
  }

  Uint8List? _decode(String value) {
    try {
      final bytes = base64Decode(value);
      return bytes.length == _keyLengthBytes ? Uint8List.fromList(bytes) : null;
    } on FormatException {
      // A malformed stored value is treated as absent so a fresh key is
      // generated instead of failing outright.
      return null;
    }
  }
}
