import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the app documents directory. Injectable so tests can point the store
/// at a temp directory without the `path_provider` platform channel.
typedef DirectoryResolver = Future<Directory> Function();

/// Durable on-device storage for queued offline-completion photos.
///
/// Mirrors [DraftPhotoStore] but keys folders by `submissionId` (NOT assetId),
/// so a queued completion's photos are immutable until it drains — a later draft
/// for the same asset can never overwrite or delete them.
///
/// Files live under `<appDocs>/outbox/<submissionId>/` and therefore survive
/// every Drift cache-wipe path (logout, manual refresh, schema migration), which
/// only ever touch DB rows.
class CompletionPhotoStore {
  const CompletionPhotoStore({DirectoryResolver? docsDir}) : _docsDir = docsDir;

  final DirectoryResolver? _docsDir;

  Future<Directory> _docs() =>
      _docsDir?.call() ?? getApplicationDocumentsDirectory();

  /// Root directory for all outbox data (`<appDocs>/outbox`).
  Future<Directory> _outboxRoot() async {
    final docs = await _docs();
    return Directory(p.join(docs.path, 'outbox'));
  }

  Future<Directory> _submissionDir(String submissionId) async {
    final root = await _outboxRoot();
    final dir = Directory(p.join(root.path, submissionId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copy [src] into the submission's photo folder and return the new durable
  /// path. If [src] already lives there (e.g. re-persisting a restored photo),
  /// it is returned unchanged rather than copied onto itself. [index] keeps the
  /// copied filenames stable and ordered.
  Future<String> persistPhoto(File src, String submissionId,
      {int? index}) async {
    final dir = await _submissionDir(submissionId);
    if (p.equals(p.dirname(src.path), dir.path)) {
      return src.path;
    }
    final ext = p.extension(src.path);
    final name = index != null ? '$index$ext' : p.basename(src.path);
    final dest = p.join(dir.path, name);
    await src.copy(dest);
    return dest;
  }

  /// Remove all photos for one submission (on submit success, supersede, or
  /// discard).
  Future<void> deleteSubmissionPhotos(String submissionId) async {
    final root = await _outboxRoot();
    final dir = Directory(p.join(root.path, submissionId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Remove every submission's photos (on logout). Leaves the manifest file
  /// (`outbox.json`) untouched — that's `OutboxStore`'s responsibility.
  Future<void> deleteAllPhotos() async {
    final root = await _outboxRoot();
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
  }

  /// The submissionIds that currently have a photo folder on disk. Used by the
  /// startup orphan sweep to delete folders with no matching manifest entry.
  Future<Set<String>> listSubmissionDirs() async {
    final root = await _outboxRoot();
    if (!await root.exists()) return {};
    final ids = <String>{};
    await for (final entity in root.list()) {
      if (entity is Directory) {
        ids.add(p.basename(entity.path));
      }
    }
    return ids;
  }
}
