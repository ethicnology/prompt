import 'dart:io';
import 'dart:typed_data';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

import '../../core/async/result.dart';
import '../../core/security/database_key_store.dart';
import '../../core/security/secure_database_key_store.dart';
import '../../features/connection/connection.dart';
import '../../features/queue/queue.dart';
import 'database_open_failure.dart';
import 'prompt_database.dart';
import 'prompt_local_storage_handle.dart';

const _databaseFileName = 'prompt.sqlite';

/// The cipher explicitly pinned for Prompt's encrypted database, rather
/// than relying on whatever SQLite3MultipleCiphers currently defaults to.
/// `chacha20` (sqleet) supports raw, already-random key material without a
/// passphrase key-derivation step, which matches a key that already comes
/// from platform secure storage.
const _cipherName = 'chacha20';

/// Opens Prompt's encrypted, on-disk local storage for Android and Linux.
///
/// Every check below runs in the calling isolate rather than inside
/// `drift_flutter`'s background database isolate, deliberately: isolates
/// share no memory, so a value only set from inside that isolate's
/// `setup` callback could never be observed here. Each failure mode is
/// instead confirmed with its own direct, synchronous `sqlite3` check
/// before drift ever opens the file:
///
/// 1. Loads (or creates) the database key from [keyStore], failing typed
///    if the platform secure storage backing it is unavailable.
/// 2. Confirms this build's `sqlite3` actually reports cipher support
///    (`PRAGMA cipher;` on a throwaway in-memory database), failing typed
///    otherwise rather than silently opening an unencrypted database.
/// 3. Detects a legacy, pre-encryption plaintext database at Prompt's
///    database path and fails typed instead of attempting an automatic,
///    in-place migration of existing plaintext data.
/// 4. Opens the real database with `PRAGMA cipher`, `PRAGMA temp_store =
///    MEMORY`, and `PRAGMA key` applied before drift issues any query of
///    its own, then immediately runs one query itself to confirm the key
///    actually unlocks that file, failing typed if it does not.
///
/// [resolveDatabasePath] overrides where that database file lives; tests
/// use this to point at a temporary directory instead of the real
/// `path_provider` application documents directory.
Future<Result<PromptLocalStorageHandle, DatabaseOpenFailure>>
openPromptLocalStorage({
  DatabaseKeyStore? keyStore,
  Future<String> Function()? resolveDatabasePath,
}) async {
  final store = keyStore ?? SecureDatabaseKeyStore();
  final Uint8List key;
  try {
    key = await store.loadOrCreateKey();
  } on DatabaseKeyStoreUnavailable {
    return const Err(DatabaseOpenFailure.keyStoreUnavailable);
  }

  if (!_cipherIsAvailable()) {
    return const Err(DatabaseOpenFailure.cipherUnavailable);
  }

  final path = await (resolveDatabasePath ?? _resolveDatabasePath)();
  if (await _isLegacyPlaintextDatabase(path)) {
    return const Err(DatabaseOpenFailure.legacyPlaintextDetected);
  }

  final hexKey = _hex(key);
  final executor = driftDatabase(
    name: 'prompt',
    native: DriftNativeOptions(
      databasePath: () async => path,
      setup: (rawDb) => rawDb
        ..execute("PRAGMA cipher = '$_cipherName';")
        ..execute('PRAGMA temp_store = MEMORY;')
        ..execute("PRAGMA key = 'raw:$hexKey';"),
    ),
  );
  final database = PromptDatabase.opened(executor);

  try {
    // Forces the executor open now, instead of at some unrelated later
    // repository call, so a key that does not unlock this file fails
    // right here.
    await database.customSelect('SELECT count(*) FROM sqlite_master;').get();
  } catch (_) {
    await database.close();
    return const Err(DatabaseOpenFailure.keyMismatchOrCorrupted);
  }

  return Ok(
    PromptLocalStorageHandle(
      serverProfiles: DriftServerProfileStore(database),
      queuedPrompts: DriftQueuePromptsDao(database),
      closeHandle: database.close,
    ),
  );
}

/// Whether this build's `sqlite3` was compiled with SQLite3MultipleCiphers
/// support, checked against a throwaway in-memory database rather than
/// the real one so this never depends on the real database's state.
bool _cipherIsAvailable() {
  final probe = sqlite3.openInMemory();
  try {
    return probe.select('PRAGMA cipher;').isNotEmpty;
  } finally {
    probe.close();
  }
}

Future<String> _resolveDatabasePath() async {
  final directory = await getApplicationDocumentsDirectory();
  return '${directory.path}${Platform.pathSeparator}$_databaseFileName';
}

/// Whether [path] already holds a database that predates
/// SQLite3MultipleCiphers encryption.
///
/// No cipher or key pragma is applied before this query: it only succeeds
/// against a file SQLite3MultipleCiphers can read as plain, unencrypted
/// SQLite. Once a file is genuinely encrypted, the same query fails
/// (`file is not a database`) without the right key, which this treats as
/// "not a legacy plaintext database" rather than guessing further.
Future<bool> _isLegacyPlaintextDatabase(String path) async {
  final file = File(path);
  if (!await file.exists() || await file.length() == 0) {
    return false;
  }
  final CommonDatabase rawDb;
  try {
    rawDb = sqlite3.open(path, mode: OpenMode.readOnly);
  } on Exception {
    return false;
  }
  try {
    rawDb.select('SELECT count(*) FROM sqlite_master;');
    return true;
  } on SqliteException {
    return false;
  } finally {
    rawDb.close();
  }
}

String _hex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
