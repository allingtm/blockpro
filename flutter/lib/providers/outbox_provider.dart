import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/outbox_entry.dart';
import '../utils/completion_photo_store.dart';
import '../utils/outbox_store.dart';
import 'drafts_provider.dart';

/// Durable outbox store — long-lived (NOT autoDispose), since a queued
/// completion must outlive any screen.
final outboxStoreProvider = Provider<OutboxStore>((ref) => OutboxStore());

/// Durable per-submission photo storage.
final completionPhotoStoreProvider =
    Provider<CompletionPhotoStore>((ref) => const CompletionPhotoStore());

/// In-memory mirror of the outbox manifest. The FILE is the source of truth;
/// this notifier holds the last-read snapshot for the UI and is refreshed after
/// every mutation (enqueue from submit, or status changes from the drainer).
class OutboxEntriesNotifier extends StateNotifier<List<OutboxEntry>> {
  OutboxEntriesNotifier(this._store) : super(const []) {
    refresh();
  }

  final OutboxStore _store;

  /// Re-read the manifest from disk into state.
  Future<void> refresh() async {
    state = await _store.readAll();
  }
}

final outboxEntriesProvider =
    StateNotifierProvider<OutboxEntriesNotifier, List<OutboxEntry>>((ref) {
  final store = ref.watch(outboxStoreProvider);
  return OutboxEntriesNotifier(store);
});

/// Count of queued completions awaiting upload — drives the global pending
/// indicator.
final pendingCountProvider = Provider<int>((ref) {
  return ref.watch(outboxEntriesProvider).length;
});

/// Asset IDs that have at least one queued completion. Survives a Drift cache
/// wipe (it's derived from the file outbox), so it keeps an asset's card showing
/// as completed/queued even after a manual refresh clears the optimistic
/// `markCompleted` row.
final pendingOutboxAssetsProvider = Provider<Set<String>>((ref) {
  return ref.watch(outboxEntriesProvider).map((e) => e.assetId).toSet();
});

/// The newest queued completion for an asset, or null. Drives re-opening an
/// asset that already has a queued completion (the screen pre-fills from this
/// rather than the deleted draft).
final assetQueuedEntryProvider =
    Provider.family<OutboxEntry?, String>((ref, assetId) {
  final entries = ref.watch(outboxEntriesProvider);
  OutboxEntry? newest;
  for (final e in entries) {
    if (e.assetId != assetId) continue;
    if (newest == null || e.createdAt >= newest.createdAt) newest = e;
  }
  return newest;
});

/// Per-asset outbox status (newest entry wins) — drives the asset-card chip.
final assetOutboxStatusProvider = Provider<Map<String, OutboxStatus>>((ref) {
  final entries = ref.watch(outboxEntriesProvider);
  final newest = <String, OutboxEntry>{};
  for (final e in entries) {
    final cur = newest[e.assetId];
    if (cur == null || e.createdAt >= cur.createdAt) newest[e.assetId] = e;
  }
  return {for (final entry in newest.entries) entry.key: entry.value.status};
});

/// Building IDs that contain at least one asset with a queued completion.
/// Mirrors [buildingsWithDraftsProvider] for the blocks list roll-up.
final buildingsWithQueuedProvider = Provider<Set<String>>((ref) {
  final queuedAssets = ref.watch(pendingOutboxAssetsProvider);
  if (queuedAssets.isEmpty) return const <String>{};
  final pairs = ref.watch(assetBuildingPairsProvider).valueOrNull ??
      const <({String assetId, String buildingId})>[];
  final buildings = <String>{};
  for (final pair in pairs) {
    if (queuedAssets.contains(pair.assetId)) buildings.add(pair.buildingId);
  }
  return buildings;
});
