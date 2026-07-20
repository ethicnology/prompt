import 'package:drift/drift.dart';

import '../../../data/local/prompt_database.dart' as db;
import '../domain/server_profile.dart';

abstract interface class ServerProfileStore {
  Future<void> save(ServerProfile profile);

  Future<ServerProfile?> loadLast();
}

class LazyServerProfileStore implements ServerProfileStore {
  LazyServerProfileStore(this._provider);

  final Future<ServerProfileStore> Function() _provider;
  ServerProfileStore? _store;

  Future<ServerProfileStore> _resolve() async {
    return _store ??= await _provider();
  }

  @override
  Future<void> save(ServerProfile profile) async {
    await (await _resolve()).save(profile);
  }

  @override
  Future<ServerProfile?> loadLast() async {
    return (await _resolve()).loadLast();
  }
}

/// Web's memory-only default: never persists past the current page
/// session, since Web has no equivalent to SQLite3MultipleCiphers-at-rest
/// encryption in this build. See `prompt_local_storage_web.dart`.
class InMemoryServerProfileStore implements ServerProfileStore {
  ServerProfile? _last;

  @override
  Future<void> save(ServerProfile profile) async {
    _last = profile;
  }

  @override
  Future<ServerProfile?> loadLast() async => _last;
}

class DriftServerProfileStore implements ServerProfileStore {
  DriftServerProfileStore(this._database);

  final db.PromptDatabase _database;

  @override
  Future<void> save(ServerProfile profile) {
    return _database
        .into(_database.serverProfiles)
        .insertOnConflictUpdate(
          db.ServerProfilesCompanion.insert(
            id: profile.id,
            origin: profile.origin.toString(),
            username: Value(profile.username),
            lastAccessedAtMillis: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<ServerProfile?> loadLast() async {
    final row =
        await (_database.select(_database.serverProfiles)
              ..orderBy([
                (table) => OrderingTerm.desc(table.lastAccessedAtMillis),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final origin = Uri.tryParse(row.origin);
    if (origin == null) {
      return null;
    }
    return ServerProfile(origin: origin, username: row.username);
  }
}
