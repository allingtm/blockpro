import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/assets_dao.dart';
import 'daos/buildings_dao.dart';
import 'daos/chapters_dao.dart';
import 'daos/drafts_dao.dart';
import 'daos/questions_dao.dart';
import 'tables/assets_table.dart';
import 'tables/buildings_table.dart';
import 'tables/chapters_table.dart';
import 'tables/draft_answers_table.dart';
import 'tables/draft_inspections_table.dart';
import 'tables/questions_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    BuildingsTable,
    AssetsTable,
    ChaptersTable,
    QuestionsTable,
    DraftInspectionsTable,
    DraftAnswersTable,
  ],
  daos: [
    BuildingsDao,
    AssetsDao,
    ChaptersDao,
    QuestionsDao,
    DraftsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing with an in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          debugPrint('DB migrating from $from to $to (drop + recreate)');
          // The local database is a disposable cache — any upgrade path
          // drops every table and recreates them. Next sync repopulates
          // from the API.
          await customStatement('PRAGMA foreign_keys = OFF');
          for (final table in allTables) {
            await customStatement(
                'DROP TABLE IF EXISTS "${table.actualTableName}"');
          }
          await m.createAll();
          await customStatement('PRAGMA foreign_keys = ON');
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
