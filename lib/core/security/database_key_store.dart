import 'dart:typed_data';

/// Creates or reuses the local database encryption key.
///
/// Implementations must never log, print, or otherwise surface the key
/// value; only [DatabaseKeyStoreUnavailable] (which never carries key
/// material) may cross this interface's boundary as a failure.
abstract interface class DatabaseKeyStore {
  /// Returns the persisted 32-byte (256-bit) database encryption key,
  /// generating and persisting a new random one on first use.
  ///
  /// Subsequent calls return the same key bytes for as long as the
  /// platform secure storage entry exists. Throws
  /// [DatabaseKeyStoreUnavailable] if that storage cannot be read or
  /// written.
  Future<Uint8List> loadOrCreateKey();
}

/// Thrown when the platform secure storage backing a [DatabaseKeyStore]
/// cannot be read or written. Never carries key material: only the
/// underlying platform exception is kept, for diagnostics that never
/// include a secret.
class DatabaseKeyStoreUnavailable implements Exception {
  const DatabaseKeyStoreUnavailable(this.cause);

  final Object cause;

  @override
  String toString() => 'DatabaseKeyStoreUnavailable: $cause';
}
