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

  /// Reactive, case-insensitive search of a building's assets. Matches anywhere
  /// in the task name or the nickname (the part shown after the dash).
  Stream<List<AssetsTableData>> watchAssetsMatching(
      String buildingId, String query) {
    final like = '%${query.toLowerCase()}%';
    return (select(assetsTable)
          ..where((t) =>
              t.buildingId.equals(buildingId) &
              (t.taskName.lower().like(like) | t.nickname.lower().like(like)))
          ..orderBy([(t) => OrderingTerm.asc(t.taskName)]))
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

  /// Stream of all (buildingId, dueDate, yellowDate) tuples. Used to derive
  /// per-building red/amber badge counts; consumers compute the counts in Dart
  /// so the status rule stays in one place ([statusForDates]).
  Stream<List<({String buildingId, DateTime? dueDate, DateTime? yellowDate})>>
      watchBuildingDueDates() {
    final query = selectOnly(assetsTable)
      ..addColumns([
        assetsTable.buildingId,
        assetsTable.dueDate,
        assetsTable.yellowDate,
      ]);
    return query.watch().map((rows) => rows
        .map((r) => (
              buildingId: r.read(assetsTable.buildingId)!,
              dueDate: r.read(assetsTable.dueDate),
              yellowDate: r.read(assetsTable.yellowDate),
            ))
        .toList());
  }

  /// Stream of all (assetId, buildingId) pairs. Used to roll asset-level
  /// signals (e.g. saved drafts) up to their building for list badges.
  Stream<List<({String assetId, String buildingId})>>
      watchAssetBuildingPairs() {
    final query = selectOnly(assetsTable)
      ..addColumns([assetsTable.id, assetsTable.buildingId]);
    return query.watch().map((rows) => rows
        .map((r) => (
              assetId: r.read(assetsTable.id)!,
              buildingId: r.read(assetsTable.buildingId)!,
            ))
        .toList());
  }

  Future<int> countAssetsForBuilding(String buildingId) async {
    final count = countAll();
    final query = selectOnly(assetsTable)
      ..addColumns([count])
      ..where(assetsTable.buildingId.equals(buildingId));
    final result = await query.getSingle();
    return result.read(count)!;
  }

  /// Returns the stored asset with [id], or `null` if it isn't in the DB.
  /// Used by the QR scanner to resolve a scanned asset id to a full asset.
  Future<AssetsTableData?> getAssetById(String id) {
    return (select(assetsTable)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
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

  // ── Mutations ──────────────────────────────────────────

  /// Optimistically mark an asset as just inspected: set [lastCompleted] and,
  /// when known, the recomputed [dueDate].
  ///
  /// A null [dueDate] leaves that column untouched so the next sync supplies the
  /// authoritative value (the local recompute can fail to parse the frequency).
  ///
  /// [yellowDate] is always written: completion invalidates the previous cycle's
  /// amber threshold, and the app can't recompute it locally (it depends on the
  /// server's per-asset offset). Pass the server's value when known, or null to
  /// clear the stale threshold so the freshly-completed asset shows green until
  /// the next sync/drain supplies a new one.
  Future<void> markCompleted(
    String assetId, {
    required DateTime lastCompleted,
    DateTime? dueDate,
    DateTime? yellowDate,
  }) {
    return (update(assetsTable)..where((t) => t.id.equals(assetId))).write(
      AssetsTableCompanion(
        lastCompleted: Value(lastCompleted),
        dueDate: dueDate == null ? const Value.absent() : Value(dueDate),
        yellowDate: Value(yellowDate),
      ),
    );
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
