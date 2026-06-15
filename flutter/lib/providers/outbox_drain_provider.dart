import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/api_repository.dart';
import '../services/outbox_drainer.dart';
import '../utils/draft_photo_store.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';
import 'database_provider.dart';
import 'outbox_provider.dart';

/// The app-wide outbox drainer. Long-lived; wired to the real stores, API, and
/// auth. `onChanged` refreshes the in-memory entries so the UI reflects each
/// status transition as the drain progresses.
final outboxDrainerProvider = Provider<OutboxDrainer>((ref) {
  final store = ref.watch(outboxStoreProvider);
  final api = ref.watch(apiRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  const draftPhotoStore = DraftPhotoStore();

  return OutboxDrainer(
    store: store,
    // Bail only when there's no hardware network — the drain's own API calls are
    // the reachability probe, so a stale "API unreachable" flag must not block
    // it. (Truly offline → SocketException → entry reverts to pending.)
    isOffline: () => !(ref.read(hasNetworkProvider).valueOrNull ?? true),
    currentUid: () => authRepo.uid,
    onChanged: () => ref.read(outboxEntriesProvider.notifier).refresh(),
    send: (entry) => replayCompletion(
      entry: entry,
      api: api,
      assetsDao: db.assetsDao,
      draftsDao: db.draftsDao,
      draftPhotoStore: draftPhotoStore,
      outbox: store,
    ),
  );
});

/// Auto-drains the outbox the moment hardware network is (re)gained. Keyed off
/// [hasNetworkProvider] rather than the combined offline signal so it fires even
/// when the API-reachability flag is still stale from the offline period. Inert
/// until a root widget keeps it alive with
/// `ref.watch(outboxDrainTriggerProvider)` (wired in Phase 4, alongside the
/// app-launch / app-resume triggers).
final outboxDrainTriggerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<bool>>(hasNetworkProvider, (prev, next) {
    final hadNetwork = prev?.valueOrNull ?? false;
    final hasNetwork = next.valueOrNull ?? false;
    if (!hadNetwork && hasNetwork) {
      ref.read(outboxDrainerProvider).drain();
    }
  });
});
