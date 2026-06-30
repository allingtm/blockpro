import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../models/question.dart';
import '../repositories/sync_repository.dart';
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

/// Reactive: `true` once the asset's checklist questions exist locally (i.e. it
/// has been downloaded). DB-only — NO sync side-effect — so it can gate entry
/// into an inspection without itself triggering a download. (Unlike
/// [checklistCountProvider], which intentionally kicks a background sync.)
final checklistDownloadedProvider =
    StreamProvider.family<bool, String>((ref, assetId) {
  final db = ref.watch(appDatabaseProvider);
  return db.questionsDao
      .watchChecklistCountForAsset(assetId)
      .map((count) => count > 0);
});

/// Status of a user-initiated checklist download from the inspection list.
enum ChecklistDownloadStatus { downloading, downloaded, error }

/// Tracks explicit, user-initiated checklist downloads from the inspection list.
///
/// A checklist must be downloaded before its inspection can be opened. On
/// success we keep a [ChecklistDownloadStatus.downloaded] marker so a
/// legitimately empty checklist (0 questions — which [checklistDownloadedProvider]
/// reports as `false`) still becomes enterable rather than looping back to a
/// Download button. The marker is in-memory only; after a full refresh wipes the
/// DB, invalidate this provider so stale markers don't outlive their data.
class ChecklistDownloadController
    extends StateNotifier<Map<String, ChecklistDownloadStatus>> {
  ChecklistDownloadController(this._sync) : super(const {});

  final SyncRepository _sync;

  Future<void> download(String assetId) async {
    if (state[assetId] == ChecklistDownloadStatus.downloading) return;
    state = {...state, assetId: ChecklistDownloadStatus.downloading};
    try {
      // force: always fetch (the asset isn't cached); rethrowOnError: surface
      // offline/auth failures instead of silently swallowing them.
      await _sync.syncChecklistForAsset(assetId,
          force: true, rethrowOnError: true);
      state = {...state, assetId: ChecklistDownloadStatus.downloaded};
    } catch (_) {
      state = {...state, assetId: ChecklistDownloadStatus.error};
    }
  }
}

final checklistDownloadControllerProvider = StateNotifierProvider<
    ChecklistDownloadController, Map<String, ChecklistDownloadStatus>>(
  (ref) => ChecklistDownloadController(ref.watch(syncRepositoryProvider)),
);

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
