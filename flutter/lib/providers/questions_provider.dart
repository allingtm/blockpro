import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/question.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

/// Streams question templates for an asset from SQLite.
/// Triggers a background sync on first watch.
final questionsStreamProvider =
    StreamProvider.family<List<Question>, String>((ref, assetId) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);

  // Fire-and-forget background sync.
  sync.syncQuestionsForAsset(assetId);

  return db.questionsDao.watchQuestionsForAsset(assetId).map(
        (rows) => rows
            .map((row) => Question(id: row.id, questionText: row.questionText))
            .toList(),
      );
});
