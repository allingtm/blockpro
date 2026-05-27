import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/buildings_table.dart';

part 'buildings_dao.g.dart';

@DriftAccessor(tables: [BuildingsTable])
class BuildingsDao extends DatabaseAccessor<AppDatabase>
    with _$BuildingsDaoMixin {
  BuildingsDao(super.db);

  // ── Reactive streams (for UI) ──────────────────────────

  Stream<List<BuildingsTableData>> watchBuildingsPaginated(
      int limit, int offset) {
    return (select(buildingsTable)
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit, offset: offset))
        .watch();
  }

  // ── One-shot queries ───────────────────────────────────

  Future<List<BuildingsTableData>> getBuildingsPaginated(
      int limit, int offset) {
    return (select(buildingsTable)
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit, offset: offset))
        .get();
  }

  Future<int> countBuildings() async {
    final count = countAll();
    final query = selectOnly(buildingsTable)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count)!;
  }

  Future<List<String>> getAllBuildingIds() async {
    final query = selectOnly(buildingsTable)
      ..addColumns([buildingsTable.id]);
    final rows = await query.get();
    return rows.map((row) => row.read(buildingsTable.id)!).toList();
  }

  // ── Upsert (API sync) ─────────────────────────────────

  Future<void> upsertBuildings(
      List<BuildingsTableCompanion> buildings) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(buildingsTable, buildings);
    });
  }

  // ── Delete ─────────────────────────────────────────────

  Future<void> deleteAllBuildings() => delete(buildingsTable).go();
}
