import 'package:drift/drift.dart';

import 'assets_table.dart';

class QuestionsTable extends Table {
  @override
  String get tableName => 'questions';

  TextColumn get id => text()();
  TextColumn get questionText => text().withDefault(const Constant(''))();
  TextColumn get description => text().nullable()();
  TextColumn get assetId =>
      text().references(AssetsTable, #id)();
  TextColumn get chapterId => text().nullable()();
  IntColumn get orderNumber => integer().withDefault(const Constant(0))();
  TextColumn get answerOption => text().nullable()();
  TextColumn get photoRequirement => text().nullable()();
  TextColumn get existingRemedials => text().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
