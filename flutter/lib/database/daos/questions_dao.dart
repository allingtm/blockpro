import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/questions_table.dart';

part 'questions_dao.g.dart';

@DriftAccessor(tables: [QuestionsTable])
class QuestionsDao extends DatabaseAccessor<AppDatabase>
    with _$QuestionsDaoMixin {
  QuestionsDao(super.db);

  Stream<List<QuestionsTableData>> watchChecklistForAsset(String assetId) {
    return (select(questionsTable)
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderNumber)]))
        .watch();
  }

  Stream<List<QuestionsTableData>> watchQuestionsForChapter(String chapterId) {
    return (select(questionsTable)
          ..where((t) => t.chapterId.equals(chapterId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderNumber)]))
        .watch();
  }

  Stream<int> watchChecklistCountForAsset(String assetId) {
    final countExp = questionsTable.id.count();
    final query = selectOnly(questionsTable)
      ..addColumns([countExp])
      ..where(questionsTable.assetId.equals(assetId));
    return query.map((row) => row.read(countExp)!).watchSingle();
  }

  Future<List<QuestionsTableData>> getChecklistForAsset(String assetId) {
    return (select(questionsTable)
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderNumber)]))
        .get();
  }

  Future<void> upsertQuestions(
      List<QuestionsTableCompanion> questions) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(questionsTable, questions);
    });
  }

  Future<void> deleteQuestionsForAsset(String assetId) {
    return (delete(questionsTable)
          ..where((t) => t.assetId.equals(assetId)))
        .go();
  }

  /// Returns the most recent `lastSyncedAt` across all questions for an asset.
  /// `null` means no questions have ever been synced for this asset.
  Future<DateTime?> getMostRecentSyncTimeForAsset(String assetId) async {
    final maxExp = questionsTable.lastSyncedAt.max();
    final query = selectOnly(questionsTable)
      ..addColumns([maxExp])
      ..where(questionsTable.assetId.equals(assetId));
    final result = await query.getSingleOrNull();
    return result?.read(maxExp);
  }
}
