import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/sync_repository.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

/// Steps shown during the initial data sync after first login.
enum SyncStep { signingIn, downloadingBuildings, complete }

/// State for the initial sync progress screen.
class InitialSyncState {
  final SyncStep currentStep;
  final String? error;

  const InitialSyncState({
    this.currentStep = SyncStep.signingIn,
    this.error,
  });

  bool get isComplete => currentStep == SyncStep.complete;
  bool get hasError => error != null;

  String get statusMessage => switch (currentStep) {
        SyncStep.signingIn => 'Signed in',
        SyncStep.downloadingBuildings => 'Downloading your buildings...',
        SyncStep.complete => 'All set!',
      };

  InitialSyncState copyWith({
    SyncStep? currentStep,
    String? error,
    bool clearError = false,
  }) {
    return InitialSyncState(
      currentStep: currentStep ?? this.currentStep,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class InitialSyncNotifier extends StateNotifier<InitialSyncState> {
  InitialSyncNotifier(this._sync)
      : super(const InitialSyncState(currentStep: SyncStep.signingIn));

  final SyncRepository _sync;

  /// Minimum time each step is shown so the progress feels deliberate.
  static const _minStepDuration = Duration(milliseconds: 800);

  /// Runs the initial data sync after login.
  Future<void> runSync() async {
    // Hold on "Signed in" step briefly.
    await Future.delayed(_minStepDuration);

    state = state.copyWith(
      currentStep: SyncStep.downloadingBuildings,
      clearError: true,
    );

    try {
      // Run the sync and the minimum display timer in parallel — the step
      // is shown for at least _minStepDuration even if the sync is instant.
      await Future.wait([
        _sync.syncBuildings(),
        Future.delayed(_minStepDuration),
      ]);
      state = state.copyWith(currentStep: SyncStep.complete);
    } catch (e) {
      debugPrint('Initial sync failed: $e');
      state = state.copyWith(error: 'Failed to download data. Please retry.');
    }
  }

  /// Retry after an error.
  Future<void> retry() async {
    await runSync();
  }
}

final initialSyncNotifierProvider =
    StateNotifierProvider.autoDispose<InitialSyncNotifier, InitialSyncState>(
        (ref) {
  final sync = ref.watch(syncRepositoryProvider);
  return InitialSyncNotifier(sync);
});

/// Returns true when the local database has no buildings (first launch or
/// post-logout). Used by the router to decide whether to show the sync screen.
final needsInitialSyncProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final count = await db.buildingsDao.countBuildings();
  return count == 0;
});
