import 'package:drift/drift.dart';

import 'assets_table.dart';

class CompletedInspectionsTable extends Table {
  @override
  String get tableName => 'completed_inspections';

  TextColumn get id => text()();
  TextColumn get assetId =>
      text().references(AssetsTable, #id)();
  DateTimeColumn get date => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
