import 'package:drift/drift.dart';

import 'completed_inspections_table.dart';

class InspectionAnswersTable extends Table {
  @override
  String get tableName => 'inspection_answers';

  IntColumn get localId => integer().autoIncrement()();
  TextColumn get inspectionId =>
      text().references(CompletedInspectionsTable, #id)();
  TextColumn get questionText => text().withDefault(const Constant(''))();
  TextColumn get answerText => text().withDefault(const Constant(''))();
}
