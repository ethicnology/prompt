import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:prompt/core/async/result.dart';
import 'package:prompt/core/security/database_key_store.dart';
import 'package:prompt/data/local/database_open_failure.dart';
import 'package:prompt/data/local/prompt_local_storage_handle.dart';
import 'package:prompt/data/local/prompt_local_storage_native.dart';
import 'package:prompt/features/connection/domain/server_profile.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3lib;

/// `driftDatabase()` calls `getTemporaryDirectory()` once per process (to
/// point `sqlite3.tempDirectory` somewhere writable) regardless of the
/// `databasePath` override this test otherwise uses, so a fake platform
/// implementation is needed even though the database path itself is
/// injected directly below.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);

  final String _path;

  @override
  Future<String?> getTemporaryPath() async => _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

class _FakeKeyStore implements DatabaseKeyStore {
  _FakeKeyStore(this._key);

  final Uint8List _key;

  @override
  Future<Uint8List> loadOrCreateKey() async => _key;
}

class _FailingKeyStore implements DatabaseKeyStore {
  @override
  Future<Uint8List> loadOrCreateKey() {
    throw const DatabaseKeyStoreUnavailable('secure storage unreachable');
  }
}

Uint8List _key(int seed) {
  return Uint8List.fromList(List<int>.generate(32, (i) => (seed + i) % 256));
}

PromptLocalStorageHandle _requireOk(
  Result<PromptLocalStorageHandle, DatabaseOpenFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('expected Ok, got Err($failure)'),
  };
}

DatabaseOpenFailure _requireErr(
  Result<PromptLocalStorageHandle, DatabaseOpenFailure> result,
) {
  return switch (result) {
    Ok() => fail('expected Err, got Ok'),
    Err(:final failure) => failure,
  };
}

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prompt-storage-test');
    dbPath = '${tempDir.path}${Platform.pathSeparator}prompt.sqlite';
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('opens a fresh database and stores/reads through it', () async {
    final handle = _requireOk(
      await openPromptLocalStorage(
        keyStore: _FakeKeyStore(_key(1)),
        resolveDatabasePath: () async => dbPath,
      ),
    );

    await handle.serverProfiles.save(
      ServerProfile(
        origin: Uri.parse('http://10.0.0.1:4096'),
        username: 'opencode',
      ),
    );
    final loaded = await handle.serverProfiles.loadLast();
    expect(loaded?.username, 'opencode');

    await handle.close();
    expect(File(dbPath).existsSync(), isTrue);
  });

  test('reopening with the same key reuses the persisted data', () async {
    final key = _key(2);
    final firstHandle = _requireOk(
      await openPromptLocalStorage(
        keyStore: _FakeKeyStore(key),
        resolveDatabasePath: () async => dbPath,
      ),
    );
    await firstHandle.serverProfiles.save(
      ServerProfile(
        origin: Uri.parse('http://10.0.0.1:4096'),
        username: 'reused',
      ),
    );
    await firstHandle.close();

    final secondHandle = _requireOk(
      await openPromptLocalStorage(
        keyStore: _FakeKeyStore(key),
        resolveDatabasePath: () async => dbPath,
      ),
    );
    final loaded = await secondHandle.serverProfiles.loadLast();
    expect(loaded?.username, 'reused');
    await secondHandle.close();
  });

  test(
    'reopening an encrypted database with the wrong key fails typed',
    () async {
      final firstHandle = _requireOk(
        await openPromptLocalStorage(
          keyStore: _FakeKeyStore(_key(3)),
          resolveDatabasePath: () async => dbPath,
        ),
      );
      await firstHandle.close();

      final failure = _requireErr(
        await openPromptLocalStorage(
          keyStore: _FakeKeyStore(_key(99)),
          resolveDatabasePath: () async => dbPath,
        ),
      );

      expect(failure, DatabaseOpenFailure.keyMismatchOrCorrupted);
    },
  );

  test('an existing legacy plaintext database fails typed instead of being '
      'silently migrated or overwritten', () async {
    final plain = sqlite3lib.sqlite3.open(dbPath);
    plain.execute('CREATE TABLE legacy (value TEXT);');
    plain.execute("INSERT INTO legacy VALUES ('unencrypted');");
    plain.close();

    final failure = _requireErr(
      await openPromptLocalStorage(
        keyStore: _FakeKeyStore(_key(4)),
        resolveDatabasePath: () async => dbPath,
      ),
    );

    expect(failure, DatabaseOpenFailure.legacyPlaintextDetected);

    // The file was never touched: still readable as plain SQLite, and
    // Prompt made no attempt to rewrite or delete it.
    final stillPlain = sqlite3lib.sqlite3.open(
      dbPath,
      mode: sqlite3lib.OpenMode.readOnly,
    );
    final rows = stillPlain.select('SELECT value FROM legacy;');
    expect(rows.first['value'], 'unencrypted');
    stillPlain.close();
  });

  test('an unavailable key store fails typed without touching the database '
      'file', () async {
    final failure = _requireErr(
      await openPromptLocalStorage(
        keyStore: _FailingKeyStore(),
        resolveDatabasePath: () async => dbPath,
      ),
    );

    expect(failure, DatabaseOpenFailure.keyStoreUnavailable);
    expect(File(dbPath).existsSync(), isFalse);
  });
}
