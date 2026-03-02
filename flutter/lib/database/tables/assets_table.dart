import 'package:drift/drift.dart';

import 'buildings_table.dart';

class AssetsTable extends Table {
  @override
  String get tableName => 'assets';

  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant('Unnamed'))();
  TextColumn get buildingId =>
      text().references(BuildingsTable, #id)();
  DateTimeColumn get nextInspection => dateTime().nullable()();
  DateTimeColumn get previousInspection => dateTime().nullable()();
  IntColumn get intervalDays => integer().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
