import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  PromptDatabase() : super(driftDatabase(name: 'prompt'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
    );
  }
}
