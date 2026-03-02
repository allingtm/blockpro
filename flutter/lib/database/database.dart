import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/assets_dao.dart';
import 'daos/buildings_dao.dart';
import 'daos/inspections_dao.dart';
import 'daos/questions_dao.dart';
import 'tables/assets_table.dart';
import 'tables/buildings_table.dart';
import 'tables/completed_inspections_table.dart';
import 'tables/inspection_answers_table.dart';
import 'tables/questions_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    BuildingsTable,
    AssetsTable,
    QuestionsTable,
    CompletedInspectionsTable,
    InspectionAnswersTable,
  ],
  daos: [
    BuildingsDao,
    AssetsDao,
    QuestionsDao,
    InspectionsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing with an in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Stepwise migrations — each version bump adds its own block.
          // Example for future version 2:
          // if (from < 2) {
          //   await m.addColumn(assetsTable, assetsTable.newColumn);
          // }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Wipe all data (e.g. on logout).
  ///
  /// Uses raw DELETE statements for speed with large datasets and
  /// temporarily disables foreign keys to avoid cascade overhead.
  Future<void> clearAllData() async {
    await customStatement('PRAGMA foreign_keys = OFF');
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
    await customStatement('PRAGMA foreign_keys = ON');
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'blockpro.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
