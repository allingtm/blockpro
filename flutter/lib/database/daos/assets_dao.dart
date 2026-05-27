import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/assets_table.dart';

part 'assets_dao.g.dart';

@DriftAccessor(tables: [AssetsTable])
class AssetsDao extends DatabaseAccessor<AppDatabase> with _$AssetsDaoMixin {
  AssetsDao(super.db);

  // ── Reactive streams (for UI) ──────────────────────────

  Stream<List<AssetsTableData>> watchAssetsPaginated(
      String buildingId, int limit, int offset) {
    return (select(assetsTable)
          ..where((t) => t.buildingId.equals(buildingId))
          ..orderBy([(t) => OrderingTerm.asc(t.taskName)])
          ..limit(limit, offset: offset))
        .watch();
  }

  // ── One-shot queries ───────────────────────────────────

  Future<List<AssetsTableData>> getAssetsPaginated(
      String buildingId, int limit, int offset) {
    return (select(assetsTable)
          ..where((t) => t.buildingId.equals(buildingId))
          ..orderBy([(t) => OrderingTerm.asc(t.taskName)])
          ..limit(limit, offset: offset))
        .get();
  }

  Future<int> countAssetsForBuilding(String buildingId) async {
    final count = countAll();
    final query = selectOnly(assetsTable)
      ..addColumns([count])
      ..where(assetsTable.buildingId.equals(buildingId));
    final result = await query.getSingle();
    return result.read(count)!;
  }

  Future<List<String>> getAllAssetIds() async {
    final query = selectOnly(assetsTable)
      ..addColumns([assetsTable.id]);
    final rows = await query.get();
    return rows.map((row) => row.read(assetsTable.id)!).toList();
  }

  /// Returns a map of assetId → checklistLastModified for all stored assets.
  /// Used by incremental sync to decide which checklists need refetching.
  Future<Map<String, DateTime?>> getChecklistLastModifiedByAsset() async {
    final query = selectOnly(assetsTable)
      ..addColumns([assetsTable.id, assetsTable.checklistLastModified]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(assetsTable.id)!:
            row.read(assetsTable.checklistLastModified),
    };
  }

  /// Returns the stored `checklistLastModified` for a single asset,
  /// or `null` if the asset isn't in the DB.
  Future<DateTime?> getChecklistLastModifiedFor(String assetId) async {
    final row = await (select(assetsTable)
          ..where((t) => t.id.equals(assetId))
          ..limit(1))
        .getSingleOrNull();
    return row?.checklistLastModified;
  }

  // ── Upsert (API sync) ─────────────────────────────────

  Future<void> upsertAssets(List<AssetsTableCompanion> assets) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(assetsTable, assets);
    });
  }

  // ── Delete ─────────────────────────────────────────────

  Future<void> deleteAssetsForBuilding(String buildingId) =>
      (delete(assetsTable)..where((t) => t.buildingId.equals(buildingId))).go();
}
