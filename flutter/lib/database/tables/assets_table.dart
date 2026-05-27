import 'package:drift/drift.dart';

import 'buildings_table.dart';

class AssetsTable extends Table {
  @override
  String get tableName => 'assets';

  TextColumn get id => text()();
  TextColumn get buildingId =>
      text().references(BuildingsTable, #id)();
  TextColumn get taskName => text().withDefault(const Constant('Unnamed'))();
  TextColumn get nickname => text().nullable()();
  TextColumn get assetRegisterItems => text().nullable()();
  TextColumn get tooltipText => text().nullable()();
  TextColumn get tooltipUrls => text().nullable()();
  DateTimeColumn get lastCompleted => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get frequency => text().nullable()();
  TextColumn get colour => text().nullable()();
  TextColumn get location => text().nullable()();
  TextColumn get floor => text().nullable()();
  DateTimeColumn get yellowDate => dateTime().nullable()();
  DateTimeColumn get assetLastModified => dateTime().nullable()();
  DateTimeColumn get checklistLastModified => dateTime().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
