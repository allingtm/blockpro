import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../repositories/sync_repository.dart';
import '../services/outbox_drainer.dart';
import '../utils/frequency.dart';
import '../utils/outbox_store.dart';
import 'database_provider.dart';
import 'outbox_drain_provider.dart';
import 'outbox_provider.dart';
import 'sync_provider.dart';

/// Steps shown during the initial data sync after first login.
enum SyncStep {
  signingIn,
  downloadingBuildings,
  downloadingAssets,
  downloadingChecklists,
  complete,
}

/// State for the initial sync progress screen.
class InitialSyncState {
  final SyncStep currentStep;
  final String? error;
  final int completed;
  final int total;

  /// False until [InitialSyncNotifier.runSync] actually begins. A never-started
  /// coordinator (returning user who skips the sync) must read as *not syncing /
  /// taps unlocked*, so the getters below all key off this.
  final bool started;

  const InitialSyncState({
    this.currentStep = SyncStep.signingIn,
    this.error,
    this.completed = 0,
    this.total = 0,
    this.started = false,
  });

  bool get isComplete => currentStep == SyncStep.complete;
  bool get hasError => error != null;

  /// True only while a sync we kicked off is actively running. Drives the
  /// refresh-disable and the pull-to-refresh no-op (false before the sync starts
  /// and after it finishes/errors).
  bool get isSyncing =>
      started && currentStep != SyncStep.complete && error == null;

  /// The sync has finished or errored — lets the blocks list choose the genuine
  /// empty state over the first-paint spinner without flashing it during the
  /// startup async gaps, and unlocks every row so none can load forever.
  bool get isSettled => currentStep == SyncStep.complete || hasError;

  /// True once the assets phase has finished (we've advanced to checklists or
  /// completed). `syncAll` awaits the entire assets pool before moving on, so at
  /// this point every building's asset fetch is done — any building that still
  /// has no asset rows (a genuinely asset-less building, or one whose count we
  /// couldn't read) can safely resolve. Used so per-row loading doesn't hang on
  /// buildings that will never gain asset rows.
  bool get assetsPhaseDone =>
      currentStep.index >= SyncStep.downloadingChecklists.index;

  String get statusMessage => switch (currentStep) {
        SyncStep.signingIn => 'Signed in',
        SyncStep.downloadingBuildings => 'Downloading buildings...',
        SyncStep.downloadingAssets => total > 0
            ? 'Downloading assets ($completed / $total blocks)'
            : 'Downloading assets...',
        SyncStep.downloadingChecklists => total > 0
            ? 'Downloading checklists ($completed / $total)'
            : 'Downloading checklists...',
        SyncStep.complete => 'All set!',
      };

  InitialSyncState copyWith({
    SyncStep? currentStep,
    String? error,
    bool clearError = false,
    int? completed,
    int? total,
    bool? started,
  }) {
    return InitialSyncState(
      currentStep: currentStep ?? this.currentStep,
      error: clearError ? null : (error ?? this.error),
      completed: completed ?? this.completed,
      total: total ?? this.total,
      started: started ?? this.started,
    );
  }
}

class InitialSyncNotifier extends StateNotifier<InitialSyncState> {
  InitialSyncNotifier(this._sync, this._db, this._outboxStore, this._drainer)
      : super(const InitialSyncState(currentStep: SyncStep.signingIn));

  final SyncRepository _sync;
  final AppDatabase _db;
  final OutboxStore _outboxStore;
  final OutboxDrainer _drainer;

  /// Guards against a second concurrent run (double initState / hot reload, or a
  /// refresh while a sync is in flight). Separate from [InitialSyncState.started]
  /// so [retry] can restart after an error without wedging.
  bool _inFlight = false;

  /// Set when the running sync should stop issuing new work — on sign-out (so it
  /// doesn't keep firing requests with the cleared token and writing into the DB
  /// that's about to be wiped) and on dispose.
  bool _cancelled = false;

  /// Runs the initial data sync in the background while the blocks list is shown
  /// (first launch / post-logout — the DB is already empty).
  Future<void> runSync() async {
    if (_inFlight) return;
    _inFlight = true;
    _cancelled = false;
    _begin();
    try {
      await _download();
    } finally {
      _inFlight = false;
    }
  }

  /// User-triggered full refresh: wipe the DB and re-download everything in the
  /// background — same UI as startup (per-building loading bars, pulsing cloud),
  /// no progress dialog — then re-assert queued completions and drain the outbox.
  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    _cancelled = false;
    _begin(); // flip to "syncing" now so the cloud shows immediately
    try {
      // Clean slate so stale/removed rows can't linger; the list empties and the
      // background-loading UI takes over (firstPaint spinner → per-building bars).
      await _db.clearAllData();
      if (_cancelled) return;
      await _download();
      if (_cancelled) return;
      // The re-synced asset due-dates come from the server, which doesn't know
      // about completions still queued in the (wipe-proof) outbox — re-apply them
      // so those assets don't flip back to overdue, then drain.
      await _reassertQueuedCompletions();
      unawaited(_drainer.drain());
    } finally {
      _inFlight = false;
    }
  }

  /// Flips state to "syncing" at the buildings phase, clearing any prior error.
  void _begin() {
    state = state.copyWith(
      started: true,
      currentStep: SyncStep.downloadingBuildings,
      clearError: true,
    );
  }

  /// Runs `syncAll`, advancing the step/progress and settling on complete/error.
  Future<void> _download() async {
    try {
      await _sync.syncAll(
        isCancelled: () => _cancelled,
        onProgress: (phase, completed, total) {
          if (!mounted || _cancelled) return;
          switch (phase) {
            case SyncPhase.buildings:
              state = state.copyWith(
                currentStep: SyncStep.downloadingBuildings,
              );
            case SyncPhase.assets:
              state = state.copyWith(
                currentStep: SyncStep.downloadingAssets,
                completed: completed,
                total: total,
              );
            case SyncPhase.checklists:
              state = state.copyWith(
                currentStep: SyncStep.downloadingChecklists,
                completed: completed,
                total: total,
              );
          }
        },
      );
      if (mounted && !_cancelled) {
        state = state.copyWith(currentStep: SyncStep.complete);
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
      if (mounted && !_cancelled) {
        state = state.copyWith(error: 'Failed to download data. Please retry.');
      }
    }
  }

  /// Re-applies the optimistic "completed" state for every asset that still has a
  /// queued completion, after a refresh has overwritten asset rows from the
  /// server.
  Future<void> _reassertQueuedCompletions() async {
    final entries = await _outboxStore.readAll();
    for (final e in entries) {
      final completedAt = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
      await _db.assetsDao.markCompleted(
        e.assetId,
        lastCompleted: completedAt,
        dueDate: nextDueDate(e.frequency, from: completedAt),
      );
    }
  }

  /// Stops a running sync from issuing further work. Called at the start of
  /// sign-out, before the token is cleared and the DB is wiped, so the sync
  /// doesn't keep firing "no token" requests. Already-in-flight requests (≤5)
  /// finish on their own; no new ones are dispatched.
  void cancel() => _cancelled = true;

  /// Retry after an error.
  Future<void> retry() async => runSync();

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }
}

final initialSyncNotifierProvider =
    StateNotifierProvider.autoDispose<InitialSyncNotifier, InitialSyncState>(
        (ref) {
  final sync = ref.watch(syncRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);
  final outboxStore = ref.watch(outboxStoreProvider);
  final drainer = ref.watch(outboxDrainerProvider);
  return InitialSyncNotifier(sync, db, outboxStore, drainer);
});

/// Returns true when the local database has no buildings (first launch or
/// post-logout). Used by the router to decide whether to show the sync screen.
final needsInitialSyncProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final count = await db.buildingsDao.countBuildings();
  return count == 0;
});
