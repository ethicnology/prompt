/// Typed failures opening Prompt's local storage.
///
/// These map platform and cipher exceptions raised while opening the
/// encrypted Android/Linux database into recoverable, user-facing states;
/// see `prompt_local_storage_native.dart`. Web never produces these: it
/// has no on-disk database to fail to open.
enum DatabaseOpenFailure {
  /// The platform secure storage that holds the database key could not be
  /// read or written.
  keyStoreUnavailable,

  /// An on-disk database file exists at Prompt's database path, but it is
  /// not encrypted with SQLite3MultipleCiphers. Prompt does not attempt an
  /// automatic in-place migration; the file must be moved aside or removed
  /// before Prompt can open a database at that path again.
  legacyPlaintextDetected,

  /// This build's `sqlite3` does not report cipher support, so the
  /// encryption pragmas in `prompt_local_storage_native.dart` could not
  /// take effect. This indicates the `hooks.user_defines.sqlite3.source`
  /// pubspec setting was not applied to this build.
  cipherUnavailable,

  /// The stored key did not unlock the on-disk database, or the database
  /// file is corrupted. Prompt cannot distinguish these two cases from the
  /// cipher's own error alone.
  keyMismatchOrCorrupted,
}

/// Thrown when Prompt's local storage could not be opened. Carries the
/// specific [DatabaseOpenFailure] so a caller can present
/// [DatabaseOpenFailureMessage.message] instead of a raw exception.
class LocalStorageUnavailableException implements Exception {
  const LocalStorageUnavailableException(this.failure);

  final DatabaseOpenFailure failure;

  @override
  String toString() => 'LocalStorageUnavailableException: ${failure.name}';
}

extension DatabaseOpenFailureMessage on DatabaseOpenFailure {
  String get message {
    return switch (this) {
      DatabaseOpenFailure.keyStoreUnavailable =>
        'Prompt cannot reach its local secure storage on this device.',
      DatabaseOpenFailure.legacyPlaintextDetected =>
        'An older, unencrypted Prompt database was found. Move it aside or '
            'delete it, then restart Prompt.',
      DatabaseOpenFailure.cipherUnavailable =>
        'This build of Prompt cannot open an encrypted local database.',
      DatabaseOpenFailure.keyMismatchOrCorrupted =>
        "Prompt cannot unlock its local database with this device's stored "
            'key.',
    };
  }
}
