import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prompt/core/security/database_key_store.dart';
import 'package:prompt/core/security/secure_database_key_store.dart';

/// An in-memory fake standing in for the platform-specific secure storage
/// implementation (Android Keystore, Linux libsecret), installed through
/// the same federated-plugin seam `flutter_secure_storage` itself uses in
/// its own tests: `FlutterSecureStoragePlatform.instance`.
class _FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};
  bool throwOnRead = false;
  bool throwOnWrite = false;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (throwOnRead) {
      throw PlatformException(code: 'unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    if (throwOnWrite) {
      throw PlatformException(code: 'unavailable');
    }
    values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }
}

void main() {
  late _FakeSecureStoragePlatform fakePlatform;
  late SecureDatabaseKeyStore keyStore;

  setUp(() {
    fakePlatform = _FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakePlatform;
    keyStore = SecureDatabaseKeyStore(const FlutterSecureStorage());
  });

  test('creates a random 32-byte key on first use and persists it', () async {
    expect(fakePlatform.values, isEmpty);

    final key = await keyStore.loadOrCreateKey();

    expect(key.length, 32);
    expect(fakePlatform.values.keys, [SecureDatabaseKeyStore.storageKey]);
  });

  test('reuses the same key across calls instead of regenerating it', () async {
    final first = await keyStore.loadOrCreateKey();
    final second = await keyStore.loadOrCreateKey();

    expect(second, first);
  });

  test('reuses the same key across a new store instance', () async {
    final first = await keyStore.loadOrCreateKey();

    final anotherStore = SecureDatabaseKeyStore(const FlutterSecureStorage());
    final second = await anotherStore.loadOrCreateKey();

    expect(second, first);
  });

  test('two keys generated for two different stored values differ', () async {
    final first = await keyStore.loadOrCreateKey();

    fakePlatform.values.clear();
    final differentStore = SecureDatabaseKeyStore(const FlutterSecureStorage());
    final second = await differentStore.loadOrCreateKey();

    expect(second, isNot(first));
  });

  test('throws DatabaseKeyStoreUnavailable, without key material, when the '
      'platform storage cannot be read', () async {
    fakePlatform.throwOnRead = true;

    await expectLater(
      keyStore.loadOrCreateKey,
      throwsA(isA<DatabaseKeyStoreUnavailable>()),
    );
  });

  test('throws DatabaseKeyStoreUnavailable when the platform storage cannot '
      'be written', () async {
    fakePlatform.throwOnWrite = true;

    await expectLater(
      keyStore.loadOrCreateKey,
      throwsA(isA<DatabaseKeyStoreUnavailable>()),
    );
  });
}
