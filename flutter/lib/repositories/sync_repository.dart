import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../utils/api_parsers.dart';
import 'api_repository.dart';

/// Progress callback for [SyncRepository.syncAll].
typedef SyncProgressCallback = void Function(SyncPhase phase, int completed, int total);

/// Phases reported during a full sync.
enum SyncPhase { buildings, assets, checklists }

/// Orchestrates API-fetch → parse → SQLite-upsert for all entity types.
class SyncRepository {
  final ApiRepository _api;
  final AppDatabase _db;

  SyncRepository(this._api, this._db);

  /// Downloads everything: buildings → assets → checklists.
  ///
  /// Incremental: during the assets phase, we capture each asset's fresh
  /// `checklistLastModified` and compare it against the value already stored.
  /// Only assets whose checklist has actually changed (or was never synced)
  /// are passed to the checklist phase — everything else is skipped.
  ///
  /// Calls [onProgress] as each phase advances.
  Future<void> syncAll({SyncProgressCallback? onProgress}) async {
    // Phase 1: Buildings
    onProgress?.call(SyncPhase.buildings, 0, 0);
    await syncBuildings();

    // Phase 2: Assets. Snapshot the stored checklist timestamps *before* we
    // overwrite them, so we can diff below.
    final storedChecklistTimestamps =
        await _db.assetsDao.getChecklistLastModifiedByAsset();
    final buildingIds = await _db.buildingsDao.getAllBuildingIds();
    onProgress?.call(SyncPhase.assets, 0, buildingIds.length);
    final freshChecklistTimestamps = <String, DateTime?>{};
    for (var i = 0; i < buildingIds.length; i++) {
      final fresh = await syncAssetsForBuilding(buildingIds[i]);
      freshChecklistTimestamps.addAll(fresh);
      onProgress?.call(SyncPhase.assets, i + 1, buildingIds.length);
    }

    // Phase 3: Checklists. Only fetch for assets whose checklistLastModified
    // changed (or for which we have no stored value).
    final staleAssetIds = <String>[];
    for (final entry in freshChecklistTimestamps.entries) {
      final stored = storedChecklistTimestamps[entry.key];
      if (_needsResync(stored: stored, fresh: entry.value)) {
        staleAssetIds.add(entry.key);
      }
    }
    debugPrint(
        'Incremental checklist sync: ${staleAssetIds.length} of ${freshChecklistTimestamps.length} assets need refresh');

    onProgress?.call(SyncPhase.checklists, 0, staleAssetIds.length);
    await _runPooled(
      items: staleAssetIds,
      maxConcurrent: 5,
      // We've already confirmed these assets are stale via the timestamp diff
      // above, so skip the per-call freshness check.
      action: (assetId) => syncChecklistForAsset(assetId, force: true),
      onItemComplete: (completed) {
        onProgress?.call(SyncPhase.checklists, completed, staleAssetIds.length);
      },
    );
  }

  /// Whether an asset's checklist needs resyncing.
  ///
  /// Rules:
  ///   - No stored value → must sync (first time seeing this asset)
  ///   - No fresh value → must sync (API didn't tell us when it last changed;
  ///     safer to fetch)
  ///   - Both present but differ → must sync
  ///   - Equal timestamps → skip
  static bool _needsResync(
      {required DateTime? stored, required DateTime? fresh}) {
    if (stored == null) return true;
    if (fresh == null) return true;
    return !stored.isAtSameMomentAs(fresh);
  }

  /// True if the locally cached checklist for [assetId] is at least as fresh
  /// as the asset's `checklistLastModified`. Used to skip redundant fetches
  /// on the per-screen background sync triggers.
  Future<bool> _isChecklistCacheCurrent(String assetId) async {
    final checklistModified =
        await _db.assetsDao.getChecklistLastModifiedFor(assetId);
    if (checklistModified == null) return false;
    final lastSynced =
        await _db.questionsDao.getMostRecentSyncTimeForAsset(assetId);
    if (lastSynced == null) return false;
    // Cache is current if we synced at or after the last-modified time.
    return !lastSynced.isBefore(checklistModified);
  }

  /// Runs [action] on each item with at most [maxConcurrent] in flight.
  Future<void> _runPooled<T>({
    required List<T> items,
    required int maxConcurrent,
    required Future<void> Function(T item) action,
    void Function(int completed)? onItemComplete,
  }) async {
    var completed = 0;
    var index = 0;
    final active = <Future<void>>{};

    Future<void> runOne(T item) async {
      await action(item);
      completed++;
      onItemComplete?.call(completed);
    }

    while (index < items.length) {
      while (active.length < maxConcurrent && index < items.length) {
        final future = runOne(items[index++]);
        active.add(future);
        future.whenComplete(() => active.remove(future));
      }
      if (active.isNotEmpty) {
        await Future.any(active);
      }
    }
    await Future.wait(active);
  }

  /// Sync all buildings from API into SQLite.
  Future<void> syncBuildings() async {
    try {
      debugPrint('── SYNC BUILDINGS ──');
      final data = await _api.authenticatedGetRaw('app_fetchbuildings');
      final buildings = parseBuildingsResponse(data);
      debugPrint('Syncing ${buildings.length} buildings to SQLite');
      final now = DateTime.now();
      final companions = buildings
          .map((b) => BuildingsTableCompanion.insert(
                id: b.id,
                name: Value(b.name),
                assetCount: Value(b.assetCount),
                lastSyncedAt: Value(now),
              ))
          .toList();
      await _db.buildingsDao.upsertBuildings(companions);
      debugPrint('── SYNC BUILDINGS COMPLETE ──');
    } catch (e) {
      debugPrint('syncBuildings failed: $e');
    }
  }

  /// Sync assets for a building from API into SQLite.
  ///
  /// Returns a map of `assetId → checklistLastModified` for every asset in
  /// the response. The caller uses this to decide which checklists to
  /// refetch in the next phase.
  Future<Map<String, DateTime?>> syncAssetsForBuilding(
      String buildingId) async {
    try {
      debugPrint('── SYNC ASSETS (building: $buildingId) ──');
      final data = await _api.authenticatedGetRaw(
        'app_fetch_all_assets',
        queryParams: {'block_id': buildingId},
      );
      final assets = parseAssetsResponse(data);
      debugPrint('Syncing ${assets.length} assets to SQLite');
      final now = DateTime.now();
      final companions = assets
          .map((a) => AssetsTableCompanion.insert(
                id: a.id,
                buildingId: buildingId,
                taskName: Value(a.taskName),
                nickname: Value(a.nickname),
                assetRegisterItems: Value(a.assetRegisterItems),
                tooltipText: Value(a.tooltipText),
                tooltipUrls: Value(a.tooltipUrls),
                lastCompleted: Value(a.lastCompleted),
                dueDate: Value(a.dueDate),
                frequency: Value(a.frequency),
                colour: Value(a.colour?.displayText),
                location: Value(a.location),
                floor: Value(a.floor),
                yellowDate: Value(a.yellowDate),
                assetLastModified: Value(a.assetLastModified),
                checklistLastModified: Value(a.checklistLastModified),
                lastSyncedAt: Value(now),
              ))
          .toList();
      await _db.assetsDao.upsertAssets(companions);
      debugPrint('── SYNC ASSETS COMPLETE ──');
      return {for (final a in assets) a.id: a.checklistLastModified};
    } catch (e) {
      debugPrint('syncAssetsForBuilding($buildingId) failed: $e');
      return const {};
    }
  }

  /// Sync checklist for an asset from API into SQLite.
  ///
  /// The v2 `app_fetch_checklist_single` response contains a hierarchy of
  /// chapters → questions → existingremedials. We persist chapters and
  /// questions to their tables; remedials are stored as a JSON blob on the
  /// question row.
  ///
  /// Set [force] to `true` to bypass the incremental check and always fetch.
  /// By default, the method is a no-op if the asset's `checklistLastModified`
  /// and `lastSyncedAt` suggest the local copy is already current.
  Future<void> syncChecklistForAsset(String assetId,
      {bool force = false}) async {
    try {
      if (!force && await _isChecklistCacheCurrent(assetId)) {
        debugPrint('── SYNC CHECKLIST (asset: $assetId) SKIPPED (up to date) ──');
        return;
      }
      debugPrint('── SYNC CHECKLIST (asset: $assetId) ──');
      final data = await _api.authenticatedGetRaw(
        'app_fetch_checklist_single',
        queryParams: {'asset_id': assetId},
      );
      final chapters = parseChecklistResponse(data);
      debugPrint('Syncing ${chapters.length} chapters to SQLite');
      final now = DateTime.now();

      final chapterCompanions = chapters
          .map((c) => ChaptersTableCompanion.insert(
                id: c.id,
                assetId: c.assetId,
                name: Value(c.name),
                orderNumber: Value(c.order),
                lastSyncedAt: Value(now),
              ))
          .toList();

      final questionCompanions = <QuestionsTableCompanion>[];
      for (final chapter in chapters) {
        for (final q in chapter.questions) {
          final remedialsJson = q.existingRemedials.isEmpty
              ? null
              : jsonEncode(q.existingRemedials.map((r) => r.toJson()).toList());
          questionCompanions.add(QuestionsTableCompanion.insert(
            id: q.id,
            questionText: Value(q.questionText),
            description: Value(q.description),
            assetId: assetId,
            chapterId: Value(q.chapterId),
            orderNumber: Value(q.orderNumber),
            answerOption: Value(q.answerOption?.displayText),
            photoRequirement: Value(q.photoRequirement?.displayText),
            existingRemedials: Value(remedialsJson),
            lastSyncedAt: Value(now),
          ));
        }
      }

      // Clean slate per-asset so removed/renamed items don't linger.
      await _db.questionsDao.deleteQuestionsForAsset(assetId);
      await _db.chaptersDao.deleteChaptersForAsset(assetId);
      await _db.chaptersDao.upsertChapters(chapterCompanions);
      await _db.questionsDao.upsertQuestions(questionCompanions);
      debugPrint(
          'Synced ${chapterCompanions.length} chapters, ${questionCompanions.length} questions');
      debugPrint('── SYNC CHECKLIST COMPLETE ──');
    } catch (e) {
      debugPrint('syncChecklistForAsset($assetId) failed: $e');
    }
  }
}
