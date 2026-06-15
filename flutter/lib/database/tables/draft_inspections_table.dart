import 'package:drift/drift.dart';

import 'assets_table.dart';

/// A locally-saved, in-progress inspection (one per asset).
///
/// Drafts never sync to the API — they exist only on the device and are deleted
/// once the inspection is submitted (or promoted to a queued offline completion).
class DraftInspectionsTable extends Table {
  @override
  String get tableName => 'draft_inspections';

  TextColumn get assetId => text().references(AssetsTable, #id)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {assetId};
}
