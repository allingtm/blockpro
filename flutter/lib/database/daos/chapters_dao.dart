import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/chapters_table.dart';

part 'chapters_dao.g.dart';

@DriftAccessor(tables: [ChaptersTable])
class ChaptersDao extends DatabaseAccessor<AppDatabase>
    with _$ChaptersDaoMixin {
  ChaptersDao(super.db);

  Stream<List<ChaptersTableData>> watchChaptersForAsset(String assetId) {
    return (select(chaptersTable)
          ..where((t) => t.assetId.equals(assetId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderNumber)]))
        .watch();
  }

  Future<void> upsertChapters(List<ChaptersTableCompanion> chapters) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(chaptersTable, chapters);
    });
  }

  Future<void> deleteChaptersForAsset(String assetId) =>
      (delete(chaptersTable)..where((t) => t.assetId.equals(assetId))).go();
}
