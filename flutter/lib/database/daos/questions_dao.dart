import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/questions_table.dart';

part 'questions_dao.g.dart';

@DriftAccessor(tables: [QuestionsTable])
class QuestionsDao extends DatabaseAccessor<AppDatabase>
    with _$QuestionsDaoMixin {
  QuestionsDao(super.db);

  // ── Reactive streams (for UI) ──────────────────────────

  Stream<List<QuestionsTableData>> watchQuestionsForAsset(
    String assetId, {
    String source = 'template',
  }) {
    return (select(questionsTable)
          ..where(
              (t) => t.assetId.equals(assetId) & t.source.equals(source)))
        .watch();
  }

  Stream<List<QuestionsTableData>> watchChecklistForAsset(String assetId) {
    return watchQuestionsForAsset(assetId, source: 'checklist');
  }

  /// Lightweight count-only stream for the checklist button label.
  Stream<int> watchChecklistCountForAsset(String assetId) {
    final countExp = questionsTable.id.count();
    final query = selectOnly(questionsTable)
      ..addColumns([countExp])
      ..where(questionsTable.assetId.equals(assetId) &
          questionsTable.source.equals('checklist'));
    return query.map((row) => row.read(countExp)!).watchSingle();
  }

  // ── One-shot queries ───────────────────────────────────

  Future<List<QuestionsTableData>> getChecklistForAsset(String assetId) {
    return (select(questionsTable)
          ..where((t) =>
              t.assetId.equals(assetId) & t.source.equals('checklist')))
        .get();
  }

  // ── Upsert (API sync) ─────────────────────────────────

  Future<void> upsertQuestions(
      List<QuestionsTableCompanion> questions) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(questionsTable, questions);
    });
  }

  // ── Delete ─────────────────────────────────────────────

  Future<void> deleteQuestionsForAsset(String assetId, {String? source}) {
    if (source != null) {
      return (delete(questionsTable)
            ..where((t) =>
                t.assetId.equals(assetId) & t.source.equals(source)))
          .go();
    }
    return (delete(questionsTable)
          ..where((t) => t.assetId.equals(assetId)))
        .go();
  }
}
