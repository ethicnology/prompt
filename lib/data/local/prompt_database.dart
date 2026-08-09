import 'package:drift/drift.dart';

part 'prompt_database.g.dart';

class ServerProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get origin => text()();
  TextColumn get username => text().nullable()();
  IntColumn get lastAccessedAtMillis => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class QueuedPrompts extends Table {
  TextColumn get id => text()();
  TextColumn get serverProfileId => text()();
  TextColumn get sessionId => text()();
  TextColumn get directory => text()();
  IntColumn get position => integer()();
  TextColumn get promptText => text()();
  TextColumn get operationType =>
      text().withDefault(const Constant('prompt'))();
  TextColumn get commandName => text().nullable()();

  /// JSON array of `{name, mediaType, base64}` objects, or null when the
  /// prompt carries no file. Stored in the encrypted database exactly like
  /// [promptText], and never logged or exported.
  TextColumn get attachmentsJson => text().nullable()();
  TextColumn get modelProviderId => text().nullable()();
  TextColumn get modelId => text().nullable()();
  TextColumn get agentName => text().nullable()();
  TextColumn get state => text()();
  TextColumn get pauseReason => text().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAtMillis => integer()();
  IntColumn get updatedAtMillis => integer()();
  IntColumn get sendingStartedAtMillis => integer().nullable()();
  IntColumn get acknowledgedAtMillis => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {serverProfileId, sessionId, position},
  ];
}

@DriftDatabase(tables: [ServerProfiles, QueuedPrompts])
class PromptDatabase extends _$PromptDatabase {
  /// Opens a [PromptDatabase] over an already-configured [QueryExecutor].
  ///
  /// Production code never opens a [QueryExecutor] here directly: see
  /// `prompt_local_storage.dart`, whose platform-specific implementations
  /// apply Android/Linux's encryption pragmas (or Web's in-memory-only
  /// default) before this class runs any query.
  PromptDatabase.opened(super.executor);

  /// Opens a [PromptDatabase] over an explicit [QueryExecutor]. Tests use
  /// this to run against an in-memory Drift executor.
  PromptDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.addColumn(
            queuedPrompts,
            queuedPrompts.modelProviderId,
          );
          await migrator.addColumn(queuedPrompts, queuedPrompts.modelId);
          await migrator.addColumn(queuedPrompts, queuedPrompts.agentName);
        }
        if (from < 3) {
          await migrator.addColumn(queuedPrompts, queuedPrompts.operationType);
          await migrator.addColumn(queuedPrompts, queuedPrompts.commandName);
        }
        if (from < 4) {
          await migrator.addColumn(
            queuedPrompts,
            queuedPrompts.attachmentsJson,
          );
        }
      },
    );
  }
}
