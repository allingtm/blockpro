import 'package:drift/drift.dart';

import 'draft_inspections_table.dart';

/// One saved answer within a draft inspection.
///
/// Keyed by [questionId] (the Bubble `questionid`) so a draft can be matched
/// back onto a freshly-loaded checklist regardless of list order. [photoPaths]
/// is a newline-joined list of durable file paths (see `draft_photo_store.dart`).
class DraftAnswersTable extends Table {
  @override
  String get tableName => 'draft_answers';

  IntColumn get localId => integer().autoIncrement()();
  TextColumn get assetId =>
      text().references(DraftInspectionsTable, #assetId)();
  TextColumn get questionId => text()();
  TextColumn get answerText => text().nullable()();
  TextColumn get photoPaths => text().nullable()();
}
