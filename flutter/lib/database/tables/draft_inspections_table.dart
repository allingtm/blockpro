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

  /// Inspection-level photo evidence — a newline-joined list of durable file
  /// paths (same convention as `DraftAnswersTable.photoPaths`).
  TextColumn get photoPaths => text().nullable()();

  /// JSON-encoded list of `RegisterItem`s the inspection is tagged with, or null.
  TextColumn get registerItemsJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {assetId};
}
