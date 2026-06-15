import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/daos/assets_dao.dart';
import '../database/daos/drafts_dao.dart';
import '../models/outbox_entry.dart';
import '../repositories/api_repository.dart';
import '../utils/draft_photo_store.dart';
import '../utils/frequency.dart';
import '../utils/outbox_store.dart';

/// Sends one queued completion to the backend. Injected into [OutboxDrainer] so
/// the single-flight / error-classification logic can be unit-tested with a fake
/// sender. The default wiring is [replayCompletion].
typedef CompletionSender = Future<void> Function(OutboxEntry entry);

/// Replays one queued completion: upload its outstanding photos, POST the
/// completed inspection, then run the same success cleanup the live submit did.
///
/// This is the SINGLE code path for sending a completion — the live "Complete"
/// tap (Phase 3) enqueues then drains, so it reaches the backend through here
/// too. Idempotency measures:
///  - photos already carrying an `uploadedImageId` are skipped;
///  - each freshly-returned `image_id` is persisted to the outbox IMMEDIATELY,
///    so a crash/retry never re-uploads a photo that already succeeded.
///
/// Throws on failure (the caller classifies the error):
///  - [SocketException] / [http.ClientException] → confirmed no-delivery, retry;
///  - anything else → ambiguous, route to [OutboxStatus.needsReview].
Future<void> replayCompletion({
  required OutboxEntry entry,
  required ApiRepository api,
  required AssetsDao assetsDao,
  required DraftsDao draftsDao,
  required DraftPhotoStore draftPhotoStore,
  required OutboxStore outbox,
}) async {
  // 1) Upload any photos that haven't uploaded yet, memoizing each image_id.
  final imageIds = <String>[];
  for (var i = 0; i < entry.photos.length; i++) {
    final photo = entry.photos[i];
    if (photo.isUploaded) {
      imageIds.add(photo.uploadedImageId!);
      continue;
    }

    final bytes = await File(photo.localPath).readAsBytes();
    final base64Image = base64Encode(bytes);
    final result = await api.authenticatedPost(
      'app_upload-image_Adam',
      body: {'base64': base64Image, 'asset_id': entry.assetId},
    );
    final imageId = result['response']?['image_id'] as String?;
    if (imageId == null) {
      // 200 but no id — anomalous. Skip rather than block the whole submission
      // (mirrors the original submit()); a re-drain won't re-upload a photo we
      // never recorded an id for, so worst case the photo is omitted.
      debugPrint('replayCompletion: upload returned no image_id for '
          '${entry.submissionId} photo $i');
      continue;
    }
    imageIds.add(imageId);
    // Persist the id before doing anything else, so an interrupted run resumes
    // without re-uploading this photo.
    final idx = i;
    await outbox.mutate(entry.submissionId, (e) {
      final photos = List<OutboxPhoto>.from(e.photos);
      photos[idx] = photos[idx].copyWith(uploadedImageId: imageId);
      return e.copyWith(photos: photos);
    });
  }

  // 2) Submit the completed inspection. Key names must match the backend:
  // each answer exposes `answer` (and `question`); `photo_ids` only when
  // present; `remedial` only on answers where the inspector raised one.
  final body = <String, dynamic>{
    'asset_id': entry.assetId,
    'answers': entry.answers
        .map((a) => {
              'answer': a.answer,
              'question': a.question,
              if (a.remedial != null) 'remedial': a.remedial!.toJson(),
            })
        .toList(),
    if (imageIds.isNotEmpty) 'photo_ids': imageIds,
  };
  await api.authenticatedPost('app_completed-inspection', body: body);

  // 3) Success — same cleanup the live submit performed. Use the enqueue time
  // (createdAt) as the completion timestamp so the optimistic due-date matches
  // when the inspection was actually done; the next sync supplies the
  // authoritative value.
  final completedAt = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
  await draftsDao.deleteDraft(entry.assetId);
  await draftPhotoStore.deleteAssetPhotos(entry.assetId);
  await assetsDao.markCompleted(
    entry.assetId,
    lastCompleted: completedAt,
    dueDate: nextDueDate(entry.frequency, from: completedAt),
  );
  await outbox.remove(entry.submissionId);
}

/// Drains the offline outbox: walks queued completions FIFO and replays each.
///
/// Guarantees:
///  - **single-flight** — `_draining` is set synchronously before any await, so
///    overlapping triggers (back-online edge + app-resume) never double-send;
///  - **at-most-once per pass** — an entry is marked `sending` before the call
///    and only removed on a confirmed success;
///  - **conservative on ambiguity** — a network error reverts to `pending` and
///    stops the pass (we're offline again); any other error → `needsReview`
///    (never blindly resent, since the server may already hold it).
class OutboxDrainer {
  OutboxDrainer({
    required OutboxStore store,
    required CompletionSender send,
    required bool Function() isOffline,
    required String? Function() currentUid,
    void Function()? onChanged,
  })  : _store = store,
        _send = send,
        _isOffline = isOffline,
        _currentUid = currentUid,
        _onChanged = onChanged;

  final OutboxStore _store;
  final CompletionSender _send;
  final bool Function() _isOffline;
  final String? Function() _currentUid;
  final void Function()? _onChanged;

  bool _draining = false;
  bool _rerunRequested = false;

  /// True while a drain pass is running. Exposed for tests/diagnostics.
  bool get isDraining => _draining;

  /// Replay every eligible entry. Safe to call from any trigger at any time.
  Future<void> drain() async {
    // Single-flight: set the flag BEFORE the first await. A call arriving while
    // we're draining just asks for one more pass (covers "came online mid-send").
    if (_draining) {
      _rerunRequested = true;
      return;
    }
    _draining = true;
    try {
      do {
        _rerunRequested = false;
        await _drainOnce();
      } while (_rerunRequested && !_isOffline());
    } finally {
      _draining = false;
      _onChanged?.call();
    }
  }

  Future<void> _drainOnce() async {
    // Recover any entry left in `sending` by an interrupted prior run, even
    // while offline — its outcome is unknown and surfacing it needs no network.
    await recoverStale();
    if (_isOffline()) return;

    final entries = await _store.readAll(); // FIFO by createdAt
    final uid = _currentUid();

    for (final entry in entries) {
      if (_isOffline()) return;
      // Cross-user safety: never send another user's queued completion.
      if (entry.uid != null && uid != null && entry.uid != uid) continue;
      if (entry.status != OutboxStatus.pending &&
          entry.status != OutboxStatus.failed) {
        continue;
      }

      // Mark sending (atomic; bumps the attempt counter) before the network call.
      final sending = await _store.mutate(
        entry.submissionId,
        (e) => e.copyWith(
          status: OutboxStatus.sending,
          attemptCount: e.attemptCount + 1,
          lastAttemptAt: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
        ),
      );
      if (sending == null) continue; // removed out from under us
      _onChanged?.call();

      try {
        await _send(sending);
        // Success: _send removed the entry and its photos.
        _onChanged?.call();
      } on SocketException catch (e) {
        // Confirmed no-delivery — revert and stop; we're offline again.
        await _store.mutate(entry.submissionId,
            (x) => x.copyWith(status: OutboxStatus.pending, lastError: '$e'));
        _onChanged?.call();
        return;
      } on http.ClientException catch (e) {
        await _store.mutate(entry.submissionId,
            (x) => x.copyWith(status: OutboxStatus.pending, lastError: '$e'));
        _onChanged?.call();
        return;
      } catch (e) {
        // Ambiguous (e.g. non-200): the server action may have run. Do NOT
        // auto-resend — surface for manual re-confirm.
        debugPrint('replayCompletion failed (ambiguous) for '
            '${entry.submissionId}: $e');
        await _store.mutate(
          entry.submissionId,
          (x) =>
              x.copyWith(status: OutboxStatus.needsReview, lastError: '$e'),
        );
        _onChanged?.call();
      }
    }
  }

  /// Move any entry stuck in [OutboxStatus.sending] (a send interrupted by a
  /// crash, outcome unknown) to [OutboxStatus.needsReview] so it is never blindly
  /// resent. Called at the start of every drain pass (and safe to call offline).
  Future<void> recoverStale() async {
    final entries = await _store.readAll();
    for (final e in entries) {
      if (e.status == OutboxStatus.sending) {
        await _store.mutate(
          e.submissionId,
          (x) => x.copyWith(
            status: OutboxStatus.needsReview,
            lastError: 'Recovered after an interrupted send',
          ),
        );
      }
    }
  }
}
