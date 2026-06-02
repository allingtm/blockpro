import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Durable on-device storage for draft inspection photos.
///
/// `image_picker` returns files in a temporary cache directory that the OS may
/// purge at any time. To keep draft photos around until the inspection is
/// submitted, we copy them into `<appDocs>/draft_photos/<assetId>/`.
class DraftPhotoStore {
  const DraftPhotoStore();

  Future<Directory> _assetDir(String assetId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'draft_photos', assetId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copy [src] into the asset's draft-photo folder and return the new path.
  ///
  /// If [src] already lives in the asset's folder (e.g. a restored draft photo
  /// being re-saved), it is returned unchanged rather than copied onto itself.
  Future<String> persistPhoto(File src, String assetId) async {
    final dir = await _assetDir(assetId);
    if (p.equals(p.dirname(src.path), dir.path)) {
      return src.path;
    }
    final dest = p.join(dir.path, p.basename(src.path));
    await src.copy(dest);
    return dest;
  }

  /// Remove all draft photos for an asset (on submit-success or draft discard).
  Future<void> deleteAssetPhotos(String assetId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'draft_photos', assetId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
