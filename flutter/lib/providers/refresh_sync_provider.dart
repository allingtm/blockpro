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

/// Phases shown in the manual-refresh loading dialog.
enum RefreshStep {
  /// No refresh has been started yet (provider's resting state). Distinct from
  /// [clearing] so the Blocks list doesn't treat the initial state as "a
  /// refresh is in progress".
  idle,
  clearing,
  downloadingBuildings,
  downloadingAssets,
  downloadingChecklists,
  complete,
  cancelled,
}

/// State for a user-triggered full data refresh from the Blocks list.
class RefreshState {
  final RefreshStep step;
  final int completed;
  final int total;

  /// Monotonic 0..1 progress for the spinner/percentage. Computed in the
  /// notifier and never allowed to go backwards, so the displayed percentage
  /// doesn't flicker as out-of-order callbacks arrive from the parallel sync.
  final double progress;

  const RefreshState({
    this.step = RefreshStep.idle,
    this.completed = 0,
    this.total = 0,
    this.progress = 0,
  });

  bool get isComplete => step == RefreshStep.complete;
  bool get isCancelled => step == RefreshStep.cancelled;
  bool get isIdle => step == RefreshStep.idle;
  bool get isRunning => !isIdle && !isComplete && !isCancelled;

  String get statusMessage => switch (step) {
        RefreshStep.idle => '',
        RefreshStep.clearing => 'Clearing local data...',
        RefreshStep.downloadingBuildings => 'Downloading buildings...',
        RefreshStep.downloadingAssets => total > 0
            ? 'Downloading assets ($completed / $total blocks)'
            : 'Downloading assets...',
        RefreshStep.downloadingChecklists => total > 0
            ? 'Downloading checklists ($completed / $total)'
            : 'Downloading checklists...',
        RefreshStep.complete => 'Done!',
        RefreshStep.cancelled => 'Cancelled',
      };

  RefreshState copyWith({
    RefreshStep? step,
    int? completed,
    int? total,
    double? progress,
  }) {
    return RefreshState(
      step: step ?? this.step,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      progress: progress ?? this.progress,
    );
  }
}

class RefreshNotifier extends StateNotifier<RefreshState> {
  RefreshNotifier(this._db, this._sync, this._outboxStore, this._drainer)
      : super(const RefreshState());

  final AppDatabase _db;
  final SyncRepository _sync;
  final OutboxStore _outboxStore;
  final OutboxDrainer _drainer;

  bool _cancelRequested = false;

  /// Wipes the local database and re-downloads everything from the API,
  /// reporting progress as it goes.
  ///
  /// If [cancel] is called mid-flight, the in-progress sync is abandoned and
  /// the database is wiped so the Blocks list shows the empty / reload state.
  Future<void> run() async {
    _cancelRequested = false;
    state = const RefreshState(step: RefreshStep.clearing, progress: 0.05);

    // Start from a clean slate so partial/stale rows can't linger.
    await _db.clearAllData();
    if (_bail()) return;

    state = state.copyWith(
      step: RefreshStep.downloadingBuildings,
      progress: _bump(0.15),
    );

    try {
      await _sync.syncAll(
        isCancelled: () => _cancelRequested,
        onProgress: (phase, completed, total) {
          if (!mounted || _cancelRequested) return;
          final targetStep = _stepFor(phase);
          // Ignore any late callback from a phase we've already moved past, so
          // counts/percentage can't snap backwards as out-of-order, pooled
          // callbacks from earlier phases trickle in.
          if (targetStep.index < state.step.index) return;
          // A new phase resets the count; within a phase counts only climb.
          final newPhase = targetStep != state.step;
          final shownCompleted =
              newPhase ? completed : (completed > state.completed
                  ? completed
                  : state.completed);
          switch (phase) {
            case SyncPhase.buildings:
              state = state.copyWith(
                step: targetStep,
                completed: 0,
                total: 0,
                progress: _bump(0.15),
              );
            case SyncPhase.assets:
              final frac = total > 0 ? shownCompleted / total : 0.0;
              state = state.copyWith(
                step: targetStep,
                completed: shownCompleted,
                total: total,
                progress: _bump(0.2 + 0.2 * frac),
              );
            case SyncPhase.checklists:
              final frac = total > 0 ? shownCompleted / total : 0.0;
              state = state.copyWith(
                step: targetStep,
                completed: shownCompleted,
                total: total,
                progress: _bump(0.4 + 0.55 * frac),
              );
          }
        },
      );
    } catch (e) {
      debugPrint('Manual refresh failed: $e');
    }

    // If the user cancelled, syncAll has stopped issuing new work and unwound.
    // Whatever partial rows it wrote before unwinding are now cleared here —
    // this single wipe runs after the sync has fully returned, so nothing can
    // write behind it. Don't overwrite the cancelled state with `complete`.
    if (_cancelRequested) {
      await _db.clearAllData();
      return;
    }

    if (mounted) {
      state = state.copyWith(step: RefreshStep.complete, progress: 1.0);
    }

    // The refresh re-synced asset due-dates from the server, which doesn't know
    // about completions still queued in the (wipe-proof) outbox. Re-apply the
    // optimistic completion so those assets don't flip back to overdue, then
    // drain now that connectivity is confirmed.
    await _reassertQueuedCompletions();
    unawaited(_drainer.drain());
  }

  /// Re-applies the optimistic "completed" state for every asset that still has
  /// a queued completion, after a refresh has overwritten asset rows from the
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

  /// Clamps [candidate] so progress only ever moves forward — out-of-order
  /// callbacks from the parallel sync can't make the percentage jump back.
  double _bump(double candidate) =>
      candidate > state.progress ? candidate.clamp(0.0, 1.0) : state.progress;

  static RefreshStep _stepFor(SyncPhase phase) => switch (phase) {
        SyncPhase.buildings => RefreshStep.downloadingBuildings,
        SyncPhase.assets => RefreshStep.downloadingAssets,
        SyncPhase.checklists => RefreshStep.downloadingChecklists,
      };

  /// Request cancellation of an in-flight refresh.
  ///
  /// Sets the flag that [SyncRepository.syncAll] polls so it stops dispatching
  /// new work and unwinds. We flip to the cancelled state immediately so the
  /// dialog closes right away, and wipe the DB now so the Blocks list empties
  /// at once instead of lingering until the in-flight requests unwind (which
  /// can take many seconds). [run] performs a second, authoritative wipe once
  /// the sync has fully returned, clearing any rows those in-flight requests
  /// wrote after this immediate wipe.
  void cancel() {
    if (_cancelRequested) return;
    _cancelRequested = true;
    if (mounted) state = state.copyWith(step: RefreshStep.cancelled);
    unawaited(_db.clearAllData());
  }

  /// If cancellation was requested before the sync started, mark it cancelled.
  /// Returns true when the caller should stop.
  bool _bail() {
    if (!_cancelRequested) return false;
    if (mounted) state = state.copyWith(step: RefreshStep.cancelled);
    return true;
  }
}

final refreshNotifierProvider =
    StateNotifierProvider<RefreshNotifier, RefreshState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);
  final outboxStore = ref.watch(outboxStoreProvider);
  final drainer = ref.watch(outboxDrainerProvider);
  return RefreshNotifier(db, sync, outboxStore, drainer);
});
