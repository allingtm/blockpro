import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/completed_inspections_table.dart';
import '../tables/inspection_answers_table.dart';

part 'inspections_dao.g.dart';

@DriftAccessor(tables: [CompletedInspectionsTable, InspectionAnswersTable])
class InspectionsDao extends DatabaseAccessor<AppDatabase>
    with _$InspectionsDaoMixin {
  InspectionsDao(super.db);

  // ── Reactive streams (for UI) ──────────────────────────

  Stream<List<CompletedInspectionsTableData>> watchInspectionsForAsset(
      String assetId) {
    return (select(completedInspectionsTable)
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  // ── One-shot queries ───────────────────────────────────

  Future<List<InspectionAnswersTableData>> getAnswersForInspection(
      String inspectionId) {
    return (select(inspectionAnswersTable)
          ..where((t) => t.inspectionId.equals(inspectionId)))
        .get();
  }

  // ── Upsert (API sync) ─────────────────────────────────

  Future<void> upsertInspection(
    CompletedInspectionsTableCompanion inspection,
    List<InspectionAnswersTableCompanion> answers,
  ) async {
    await transaction(() async {
      await into(completedInspectionsTable)
          .insertOnConflictUpdate(inspection);
      // Delete old answers, re-insert new ones
      final inspId = inspection.id.value;
      await (delete(inspectionAnswersTable)
            ..where((t) => t.inspectionId.equals(inspId)))
          .go();
      await batch((b) {
        b.insertAll(inspectionAnswersTable, answers);
      });
    });
  }
}
