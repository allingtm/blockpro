import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/outbox_entry.dart';
import 'completion_photo_store.dart';

/// Durable, wipe-proof queue of offline completions, stored as a single JSON
/// manifest at `<appDocs>/outbox/outbox.json` plus per-submission photo folders.
///
/// The **file is the single source of truth.** All mutations serialize behind
/// one async mutex and write atomically (write `*.tmp`, then rename over the
/// target), so a concurrent enqueue/update or a kill mid-write can never tear
/// the file or lose an entry. A missing or corrupt manifest reads as empty.
///
/// Nothing here lives in Drift, so `AppDatabase.clearAllData()` (logout / manual
/// refresh) and the drop-all schema migration leave the queue fully intact.
class OutboxStore {
  OutboxStore({
    DirectoryResolver? docsDir,
    CompletionPhotoStore? photoStore,
  })  : _docsDir = docsDir,
        _photos = photoStore ?? CompletionPhotoStore(docsDir: docsDir);

  final DirectoryResolver? _docsDir;
  final CompletionPhotoStore _photos;

  static const _manifestVersion = 1;

  /// Tail of the mutex chain. Each call awaits the previous segment before
  /// running, then releases the next. Assigned synchronously so concurrent
  /// callers queue deterministically in call order.
  Future<void> _lock = Future.value();

  Future<T> _withLock<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _lock;
    _lock = completer.future;
    return previous
        .then((_) => action())
        .whenComplete(() => completer.complete());
  }

  Future<File> _manifestFile() async {
    final docs = await (_docsDir?.call() ?? getApplicationDocumentsDirectory());
    final dir = Directory(p.join(docs.path, 'outbox'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'outbox.json'));
  }

  /// Raw read with no locking. Tolerates a missing/corrupt/empty file by
  /// returning an empty list.
  Future<List<OutboxEntry>> _readUnlocked() async {
    try {
      final file = await _manifestFile();
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.trim().isEmpty) return [];
      final json = jsonDecode(text) as Map<String, dynamic>;
      return (json['entries'] as List<dynamic>? ?? const [])
          .map((e) => OutboxEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('OutboxStore: unreadable manifest, treating as empty: $e');
      return [];
    }
  }

  /// Atomic write: serialize to `outbox.json.tmp`, then rename over the target
  /// (rename is atomic on the same volume), so a kill can never leave a torn
  /// manifest.
  Future<void> _writeUnlocked(List<OutboxEntry> entries) async {
    final file = await _manifestFile();
    final tmp = File('${file.path}.tmp');
    final payload = jsonEncode({
      'version': _manifestVersion,
      'entries': entries.map((e) => e.toJson()).toList(),
    });
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(file.path);
  }

  /// All queued entries, FIFO by [OutboxEntry.createdAt]. Reads take the lock so
  /// they never observe a half-applied mutation.
  Future<List<OutboxEntry>> readAll() {
    return _withLock(() async {
      final entries = await _readUnlocked();
      entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return entries;
    });
  }

  /// Append [entry], or replace any existing entry with the same submissionId
  /// (supersede). Photo files are NOT touched here — the caller persists them
  /// before enqueuing, and `remove`/supersede cleans up the old folder.
  Future<void> enqueue(OutboxEntry entry) {
    return _withLock(() async {
      final entries = await _readUnlocked();
      entries.removeWhere((e) => e.submissionId == entry.submissionId);
      entries.add(entry);
      await _writeUnlocked(entries);
    });
  }

  /// Replace the entry with the same submissionId in place. No-op if absent.
  Future<void> update(OutboxEntry entry) {
    return _withLock(() async {
      final entries = await _readUnlocked();
      final idx =
          entries.indexWhere((e) => e.submissionId == entry.submissionId);
      if (idx == -1) return;
      entries[idx] = entry;
      await _writeUnlocked(entries);
    });
  }

  /// Atomic read-modify-write of one entry, all inside the lock.
  ///
  /// [transform] receives the CURRENT on-disk entry and returns the updated one;
  /// it is not called if the entry is absent. Returns the updated entry, or null
  /// if absent. Use this (not [update]) whenever two writers might touch the same
  /// entry concurrently — e.g. the drainer flipping status while a photo upload
  /// memoizes its `image_id` — so neither clobbers the other's field from a stale
  /// snapshot.
  Future<OutboxEntry?> mutate(
    String submissionId,
    OutboxEntry Function(OutboxEntry current) transform,
  ) {
    return _withLock(() async {
      final entries = await _readUnlocked();
      final idx = entries.indexWhere((e) => e.submissionId == submissionId);
      if (idx == -1) return null;
      final updated = transform(entries[idx]);
      entries[idx] = updated;
      await _writeUnlocked(entries);
      return updated;
    });
  }

  /// The single entry with [submissionId], or null if absent.
  Future<OutboxEntry?> getById(String submissionId) {
    return _withLock(() async {
      final entries = await _readUnlocked();
      for (final e in entries) {
        if (e.submissionId == submissionId) return e;
      }
      return null;
    });
  }

  /// Remove an entry and delete its photo folder.
  Future<void> remove(String submissionId) {
    return _withLock(() async {
      final entries = await _readUnlocked();
      entries.removeWhere((e) => e.submissionId == submissionId);
      await _writeUnlocked(entries);
      await _photos.deleteSubmissionPhotos(submissionId);
    });
  }

  /// Empty the queue and delete all photos (on logout).
  Future<void> clearAll() {
    return _withLock(() async {
      await _writeUnlocked(const []);
      await _photos.deleteAllPhotos();
    });
  }

  /// Delete photo folders that have no matching manifest entry — e.g. left by a
  /// crash between persisting photos and writing the entry, or by a superseded
  /// entry. Safe to call at startup.
  ///
  /// Does NOT delete manifest entries: whether an entry with a missing photo is
  /// still submittable is a drain-time decision (the drainer can route it to
  /// [OutboxStatus.needsReview]), not a silent deletion here.
  Future<void> sweepOrphanPhotoDirs() {
    return _withLock(() async {
      final entries = await _readUnlocked();
      final known = entries.map((e) => e.submissionId).toSet();
      final dirs = await _photos.listSubmissionDirs();
      for (final id in dirs) {
        if (!known.contains(id)) {
          await _photos.deleteSubmissionPhotos(id);
        }
      }
    });
  }
}
