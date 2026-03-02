import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../models/building.dart';
import '../repositories/sync_repository.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

const _pageSize = 20;

/// State for a paginated buildings list.
class PaginatedBuildingsState {
  final List<Building> items;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSyncing;
  final int currentOffset;

  const PaginatedBuildingsState({
    this.items = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isSyncing = false,
    this.currentOffset = 0,
  });

  PaginatedBuildingsState copyWith({
    List<Building>? items,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSyncing,
    int? currentOffset,
  }) {
    return PaginatedBuildingsState(
      items: items ?? this.items,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      isSyncing: isSyncing ?? this.isSyncing,
      currentOffset: currentOffset ?? this.currentOffset,
    );
  }

  /// True when we have no cached data and are still waiting for the first sync.
  bool get isInitialLoading => items.isEmpty && isSyncing;
}

class PaginatedBuildingsNotifier
    extends StateNotifier<PaginatedBuildingsState> {
  PaginatedBuildingsNotifier(this._db, this._sync)
      : super(const PaginatedBuildingsState()) {
    _init();
  }

  final AppDatabase _db;
  final SyncRepository _sync;
  StreamSubscription<List<BuildingsTableData>>? _subscription;

  Future<void> _init() async {
    // Load first page from SQLite immediately (may be empty on first launch).
    await _loadPage(0);

    // Start listening for DB changes so the UI auto-updates after sync.
    _subscription = _db.buildingsDao
        .watchBuildingsPaginated(_pageSize, 0)
        .listen((_) {
      // When the DB changes, reload current window.
      _reloadCurrentWindow();
    });

    // Only trigger background sync if the DB is empty (first launch without
    // going through the initial sync screen). If the sync screen already
    // populated the DB, skip to avoid a redundant API call.
    final count = await _db.buildingsDao.countBuildings();
    if (count == 0) {
      _triggerSync();
    }
  }

  Future<void> _triggerSync() async {
    state = state.copyWith(isSyncing: true);
    await _sync.syncBuildings();
    state = state.copyWith(isSyncing: false);
  }

  Future<void> _loadPage(int offset) async {
    final rows =
        await _db.buildingsDao.getBuildingsPaginated(_pageSize, offset);
    final buildings = rows.map(_toBuilding).toList();
    final total = await _db.buildingsDao.countBuildings();

    if (offset == 0) {
      state = state.copyWith(
        items: buildings,
        currentOffset: buildings.length,
        hasMore: buildings.length < total,
      );
    } else {
      state = state.copyWith(
        items: [...state.items, ...buildings],
        currentOffset: state.currentOffset + buildings.length,
        hasMore: state.currentOffset + buildings.length < total,
        isLoadingMore: false,
      );
    }
  }

  Future<void> _reloadCurrentWindow() async {
    final total = await _db.buildingsDao.countBuildings();
    // Reload all items up to the current offset (or at least one page).
    final limit =
        state.currentOffset > 0 ? state.currentOffset : _pageSize;
    final rows = await _db.buildingsDao.getBuildingsPaginated(limit, 0);
    final buildings = rows.map(_toBuilding).toList();
    state = state.copyWith(
      items: buildings,
      currentOffset: buildings.length,
      hasMore: buildings.length < total,
    );
  }

  /// Load the next page. Called when the user scrolls near the bottom.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _loadPage(state.currentOffset);
  }

  /// Pull-to-refresh: sync from API then reload.
  Future<void> refresh() async {
    await _triggerSync();
    await _reloadCurrentWindow();
  }

  static Building _toBuilding(BuildingsTableData row) {
    return Building(
      id: row.id,
      name: row.name,
      assetCount: row.assetCount,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final buildingsNotifierProvider = StateNotifierProvider<
    PaginatedBuildingsNotifier, PaginatedBuildingsState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);
  return PaginatedBuildingsNotifier(db, sync);
});
