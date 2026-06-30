import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../models/question.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

/// Streams the full checklist for an asset as a list of Chapters (each with
/// its nested questions).
///
/// On first watch, if the asset has no local checklist yet, this *blocks* on the
/// download so the screen stays in its loading state (rather than flashing an
/// empty form) and a download failure surfaces as an error → Retry. If a local
/// copy already exists it's shown immediately and refreshed in the background.
final checklistChaptersStreamProvider =
    StreamProvider.family<List<Chapter>, String>((ref, assetId) {
  // Read dependencies synchronously here so Riverpod tracks them; the async*
  // closure below runs lazily on listen.
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);

  Stream<List<Chapter>> watch() async* {
    final hasLocal =
        await db.questionsDao.getMostRecentSyncTimeForAsset(assetId) != null;
    if (hasLocal) {
      // Show the cached copy now; refresh in the background (failures ignored).
      sync.syncChecklistForAsset(assetId);
    } else {
      // Nothing cached — block on the download so the screen shows its spinner,
      // and surface a failure (offline/auth) as an error instead of a blank form.
      await sync.syncChecklistForAsset(assetId, rethrowOnError: true);
    }

    // Combine chapters + questions streams into a hierarchical list.
    yield* db.chaptersDao
        .watchChaptersForAsset(assetId)
        .asyncMap((chapterRows) async {
      final questionRows = await db.questionsDao.getChecklistForAsset(assetId);
      final questionsByChapter = <String, List<Question>>{};
      for (final q in questionRows) {
        final chapterId = q.chapterId ?? '';
        (questionsByChapter[chapterId] ??= []).add(_toQuestion(q));
      }
      return chapterRows
          .map((c) => Chapter(
                id: c.id,
                assetId: c.assetId,
                name: c.name,
                order: c.orderNumber,
                questions: questionsByChapter[c.id] ?? const [],
              ))
          .toList();
    });
  }

  return watch();
});

/// Lightweight count-only stream for the asset detail button label.
final checklistCountProvider =
    StreamProvider.family<int, String>((ref, assetId) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);

  sync.syncChecklistForAsset(assetId);

  return db.questionsDao.watchChecklistCountForAsset(assetId);
});

Question _toQuestion(QuestionsTableData row) {
  final remedialsRaw = row.existingRemedials;
  final remedials = <Remedial>[];
  if (remedialsRaw != null && remedialsRaw.isNotEmpty) {
    final decoded = jsonDecode(remedialsRaw);
    if (decoded is List) {
      for (final r in decoded.whereType<Map<String, dynamic>>()) {
        remedials.add(Remedial.fromJson(r));
      }
    }
  }
  return Question(
    id: row.id,
    questionText: row.questionText,
    description: row.description,
    chapterId: row.chapterId ?? '',
    orderNumber: row.orderNumber,
    answerOption: AnswerOption.fromString(row.answerOption),
    photoRequirement: PhotoRequirement.fromString(row.photoRequirement),
    existingRemedials: remedials,
  );
}
