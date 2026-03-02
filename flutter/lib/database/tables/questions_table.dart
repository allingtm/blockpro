import 'package:drift/drift.dart';

import 'assets_table.dart';

class QuestionsTable extends Table {
  @override
  String get tableName => 'questions';

  TextColumn get id => text()();
  TextColumn get questionText => text().withDefault(const Constant(''))();
  TextColumn get assetId =>
      text().references(AssetsTable, #id)();
  TextColumn get source =>
      text().withDefault(const Constant('template'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
