import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../utils/api_parsers.dart';
import 'api_repository.dart';

/// Orchestrates API-fetch → parse → SQLite-upsert for all entity types.
class SyncRepository {
  final ApiRepository _api;
  final AppDatabase _db;

  SyncRepository(this._api, this._db);

  /// Sync all buildings from API into SQLite.
  Future<void> syncBuildings() async {
    try {
      debugPrint('── SYNC BUILDINGS ──');
      final data = await _api.authenticatedGetRaw('fetchbuildings');
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
  Future<void> syncAssetsForBuilding(String buildingId) async {
    try {
      debugPrint('── SYNC ASSETS (building: $buildingId) ──');
      final data = await _api.authenticatedGetRaw(
        'fetchassets',
        queryParams: {'block_id': buildingId},
      );
      final assets = parseAssetsResponse(data);
      debugPrint('Syncing ${assets.length} assets to SQLite');
      final now = DateTime.now();
      final companions = assets
          .map((a) => AssetsTableCompanion.insert(
                id: a.id,
                name: Value(a.name),
                buildingId: buildingId,
                nextInspection: Value(a.nextInspection),
                previousInspection: Value(a.previousInspection),
                intervalDays: Value(a.intervalDays),
                lastSyncedAt: Value(now),
              ))
          .toList();
      await _db.assetsDao.upsertAssets(companions);
      debugPrint('── SYNC ASSETS COMPLETE ──');
    } catch (e) {
      debugPrint('syncAssetsForBuilding($buildingId) failed: $e');
    }
  }

  /// Sync question templates for an asset from API into SQLite.
  Future<void> syncQuestionsForAsset(String assetId) async {
    try {
      debugPrint('── SYNC QUESTIONS (asset: $assetId) ──');
      final data = await _api.authenticatedGetRaw(
        'fetchquestions',
        queryParams: {'asset_id': assetId},
      );
      final questions = parseQuestionsResponse(data);
      debugPrint('Syncing ${questions.length} questions to SQLite');
      final now = DateTime.now();
      final companions = questions
          .map((q) => QuestionsTableCompanion.insert(
                id: q.id,
                questionText: Value(q.questionText),
                assetId: assetId,
                source: const Value('template'),
                lastSyncedAt: Value(now),
              ))
          .toList();
      await _db.questionsDao.upsertQuestions(companions);
      debugPrint('── SYNC QUESTIONS COMPLETE ──');
    } catch (e) {
      debugPrint('syncQuestionsForAsset($assetId) failed: $e');
    }
  }

  /// Sync checklist for an asset from API into SQLite.
  Future<void> syncChecklistForAsset(String assetId) async {
    try {
      debugPrint('── SYNC CHECKLIST (asset: $assetId) ──');
      final data = await _api.authenticatedGetRaw(
        'fetchchecklist',
        queryParams: {'asset_id': assetId},
      );
      final questions = parseChecklistResponse(data);
      debugPrint('Syncing ${questions.length} checklist items to SQLite');
      final now = DateTime.now();
      final companions = questions
          .map((q) => QuestionsTableCompanion.insert(
                id: q.id,
                questionText: Value(q.questionText),
                assetId: assetId,
                source: const Value('checklist'),
                lastSyncedAt: Value(now),
              ))
          .toList();
      await _db.questionsDao.upsertQuestions(companions);
      debugPrint('── SYNC CHECKLIST COMPLETE ──');
    } catch (e) {
      debugPrint('syncChecklistForAsset($assetId) failed: $e');
    }
  }
}
