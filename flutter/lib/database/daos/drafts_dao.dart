import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/draft_answers_table.dart';
import '../tables/draft_inspections_table.dart';

part 'drafts_dao.g.dart';

@DriftAccessor(tables: [DraftInspectionsTable, DraftAnswersTable])
class DraftsDao extends DatabaseAccessor<AppDatabase>
    with _$DraftsDaoMixin {
  DraftsDao(super.db);

  // ── Reactive streams (for UI) ──────────────────────────

  /// Asset IDs that currently have a saved draft — used for the "Draft" badge.
  Stream<Set<String>> watchAssetIdsWithDrafts() {
    final query = selectOnly(draftInspectionsTable)
      ..addColumns([draftInspectionsTable.assetId]);
    return query.watch().map((rows) =>
        rows.map((r) => r.read(draftInspectionsTable.assetId)!).toSet());
  }

  // ── One-shot queries ───────────────────────────────────

  Future<List<DraftAnswersTableData>> getDraftAnswers(String assetId) {
    return (select(draftAnswersTable)
          ..where((t) => t.assetId.equals(assetId)))
        .get();
  }

  Future<bool> hasDraft(String assetId) async {
    final row = await (select(draftInspectionsTable)
          ..where((t) => t.assetId.equals(assetId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  // ── Mutations ──────────────────────────────────────────

  /// Upsert a draft for [assetId], replacing any previously-saved answers.
  Future<void> saveDraft(
    String assetId,
    List<DraftAnswersTableCompanion> answers,
  ) async {
    await transaction(() async {
      await into(draftInspectionsTable).insertOnConflictUpdate(
        DraftInspectionsTableCompanion.insert(
          assetId: assetId,
          updatedAt: DateTime.now(),
        ),
      );
      await (delete(draftAnswersTable)
            ..where((t) => t.assetId.equals(assetId)))
          .go();
      await batch((b) {
        b.insertAll(draftAnswersTable, answers);
      });
    });
  }

  Future<void> deleteDraft(String assetId) async {
    await transaction(() async {
      await (delete(draftAnswersTable)
            ..where((t) => t.assetId.equals(assetId)))
          .go();
      await (delete(draftInspectionsTable)
            ..where((t) => t.assetId.equals(assetId)))
          .go();
    });
  }
}
