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
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit, offset: offset))
        .watch();
  }

  // ── One-shot queries ───────────────────────────────────

  Future<List<AssetsTableData>> getAssetsPaginated(
      String buildingId, int limit, int offset) {
    return (select(assetsTable)
          ..where((t) => t.buildingId.equals(buildingId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
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
