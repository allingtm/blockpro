import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/question.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

/// Streams checklist questions for an asset from SQLite.
/// Triggers a background sync on first watch.
final checklistStreamProvider =
    StreamProvider.family<List<Question>, String>((ref, assetId) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);

  // Fire-and-forget background sync.
  sync.syncChecklistForAsset(assetId);

  return db.questionsDao.watchChecklistForAsset(assetId).map(
        (rows) => rows
            .map((row) => Question(id: row.id, questionText: row.questionText))
            .toList(),
      );
});

/// Lightweight count-only stream for the asset detail button label.
/// Avoids loading all question objects into memory.
final checklistCountProvider =
    StreamProvider.family<int, String>((ref, assetId) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);

  // Fire-and-forget background sync.
  sync.syncChecklistForAsset(assetId);

  return db.questionsDao.watchChecklistCountForAsset(assetId);
});
