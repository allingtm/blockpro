import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';

/// A single restored draft answer for a question.
class DraftAnswer {
  final String? answerText;
  final List<String> photoPaths;

  const DraftAnswer({this.answerText, this.photoPaths = const []});
}

/// Loads the saved draft for an asset as a `questionId -> DraftAnswer` map.
///
/// Returns an empty map when no draft exists. The inspection screen uses this
/// to pre-fill answers and rebuild photos when reopening an asset.
final draftAnswersProvider = FutureProvider.autoDispose
    .family<Map<String, DraftAnswer>, String>((ref, assetId) async {
  final draftsDao = ref.watch(appDatabaseProvider).draftsDao;
  final rows = await draftsDao.getDraftAnswers(assetId);
  return {
    for (final row in rows)
      row.questionId: DraftAnswer(
        answerText: row.answerText,
        photoPaths: (row.photoPaths == null || row.photoPaths!.isEmpty)
            ? const []
            : row.photoPaths!.split('\n'),
      ),
  };
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
