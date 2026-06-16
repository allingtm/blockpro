import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/new_remedial.dart';
import '../models/register_item.dart';
import 'database_provider.dart';

/// A single restored draft answer for a question.
class DraftAnswer {
  final String? answerText;
  final List<String> photoPaths;
  final NewRemedial? remedial;

  const DraftAnswer({
    this.answerText,
    this.photoPaths = const [],
    this.remedial,
  });

  /// Decode a draft row's `remedialJson` column; null on missing/malformed.
  static NewRemedial? decodeRemedial(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return NewRemedial.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// A restored draft inspection: per-question answers plus the inspection-level
/// photo evidence and tagged register items.
class DraftInspection {
  final Map<String, DraftAnswer> answers;
  final List<String> photoPaths;
  final List<RegisterItem> registerItems;

  const DraftInspection({
    this.answers = const {},
    this.photoPaths = const [],
    this.registerItems = const [],
  });

  /// True when no draft exists (no answers, photos, or tagged items).
  bool get isEmpty =>
      answers.isEmpty && photoPaths.isEmpty && registerItems.isEmpty;

  /// Decode the draft inspection row's `registerItemsJson` column.
  static List<RegisterItem> decodeRegisterItems(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(RegisterItem.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static List<String> _splitPaths(String? raw) =>
      (raw == null || raw.isEmpty) ? const [] : raw.split('\n');
}

/// Loads the saved draft for an asset (answers + inspection-level photos and
/// register items).
///
/// Returns an empty [DraftInspection] when no draft exists. The inspection
/// screen uses this to pre-fill answers, photos, and register-item tags when
/// reopening an asset.
final draftAnswersProvider = FutureProvider.autoDispose
    .family<DraftInspection, String>((ref, assetId) async {
  final draftsDao = ref.watch(appDatabaseProvider).draftsDao;
  final rows = await draftsDao.getDraftAnswers(assetId);
  final inspection = await draftsDao.getDraftInspection(assetId);
  return DraftInspection(
    answers: {
      for (final row in rows)
        row.questionId: DraftAnswer(
          answerText: row.answerText,
          photoPaths: DraftInspection._splitPaths(row.photoPaths),
          remedial: DraftAnswer.decodeRemedial(row.remedialJson),
        ),
    },
    photoPaths: DraftInspection._splitPaths(inspection?.photoPaths),
    registerItems:
        DraftInspection.decodeRegisterItems(inspection?.registerItemsJson),
  );
});

/// Set of asset IDs that currently have a saved draft — drives the Draft badge.
final assetDraftsProvider = StreamProvider<Set<String>>((ref) {
  final draftsDao = ref.watch(appDatabaseProvider).draftsDao;
  return draftsDao.watchAssetIdsWithDrafts();
});

/// Set of building IDs that contain at least one asset with a saved draft.
/// Rolls [assetDraftsProvider] up to the building level for the blocks list.
final buildingsWithDraftsProvider = Provider<Set<String>>((ref) {
  final draftAssets =
      ref.watch(assetDraftsProvider).valueOrNull ?? const <String>{};
  if (draftAssets.isEmpty) return const <String>{};
  final pairs = ref.watch(assetBuildingPairsProvider).valueOrNull ??
      const <({String assetId, String buildingId})>[];
  final buildings = <String>{};
  for (final pair in pairs) {
    if (draftAssets.contains(pair.assetId)) buildings.add(pair.buildingId);
  }
  return buildings;
});

/// (assetId, buildingId) pairs from the assets table, for draft roll-up.
final assetBuildingPairsProvider =
    StreamProvider<List<({String assetId, String buildingId})>>((ref) {
  final assetsDao = ref.watch(appDatabaseProvider).assetsDao;
  return assetsDao.watchAssetBuildingPairs();
});
