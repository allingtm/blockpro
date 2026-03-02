import 'package:drift/drift.dart';

class BuildingsTable extends Table {
  @override
  String get tableName => 'buildings';

  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant('Unnamed'))();
  IntColumn get assetCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
