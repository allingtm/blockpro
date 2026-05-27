import 'package:drift/drift.dart';

import 'assets_table.dart';

class ChaptersTable extends Table {
  @override
  String get tableName => 'chapters';

  TextColumn get id => text()();
  TextColumn get assetId => text().references(AssetsTable, #id)();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get orderNumber => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
