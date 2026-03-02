import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../models/asset.dart';
import '../repositories/sync_repository.dart';
import 'database_provider.dart';
import 'sync_provider.dart';

const _pageSize = 20;

/// State for a paginated assets list.
class PaginatedAssetsState {
  final List<Asset> items;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isSyncing;
  final int currentOffset;

  const PaginatedAssetsState({
    this.items = const [],
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isSyncing = false,
    this.currentOffset = 0,
  });

  PaginatedAssetsState copyWith({
    List<Asset>? items,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isSyncing,
    int? currentOffset,
  }) {
    return PaginatedAssetsState(
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

class PaginatedAssetsNotifier extends StateNotifier<PaginatedAssetsState> {
  PaginatedAssetsNotifier(this._db, this._sync, this._buildingId)
      : super(const PaginatedAssetsState(isSyncing: true)) {
    _init();
  }

  final AppDatabase _db;
  final SyncRepository _sync;
  final String _buildingId;
  StreamSubscription<List<AssetsTableData>>? _subscription;

  Future<void> _init() async {
    await _loadPage(0);

    _subscription = _db.assetsDao
        .watchAssetsPaginated(_buildingId, _pageSize, 0)
        .listen((_) {
      _reloadCurrentWindow();
    });

    _triggerSync();
  }

  Future<void> _triggerSync() async {
    state = state.copyWith(isSyncing: true);
    await _sync.syncAssetsForBuilding(_buildingId);
    state = state.copyWith(isSyncing: false);
  }

  Future<void> _loadPage(int offset) async {
    final rows = await _db.assetsDao
        .getAssetsPaginated(_buildingId, _pageSize, offset);
    final assets = rows.map(_toAsset).toList();
    final total = await _db.assetsDao.countAssetsForBuilding(_buildingId);

    if (offset == 0) {
      state = state.copyWith(
        items: assets,
        currentOffset: assets.length,
        hasMore: assets.length < total,
      );
    } else {
      state = state.copyWith(
        items: [...state.items, ...assets],
        currentOffset: state.currentOffset + assets.length,
        hasMore: state.currentOffset + assets.length < total,
        isLoadingMore: false,
      );
    }
  }

  Future<void> _reloadCurrentWindow() async {
    final total = await _db.assetsDao.countAssetsForBuilding(_buildingId);
    final limit =
        state.currentOffset > 0 ? state.currentOffset : _pageSize;
    final rows =
        await _db.assetsDao.getAssetsPaginated(_buildingId, limit, 0);
    final assets = rows.map(_toAsset).toList();
    state = state.copyWith(
      items: assets,
      currentOffset: assets.length,
      hasMore: assets.length < total,
    );
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _loadPage(state.currentOffset);
  }

  Future<void> refresh() async {
    await _triggerSync();
    await _reloadCurrentWindow();
  }

  static Asset _toAsset(AssetsTableData row) {
    return Asset(
      id: row.id,
      name: row.name,
      nextInspection: row.nextInspection,
      previousInspection: row.previousInspection,
      intervalDays: row.intervalDays,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Provider family keyed by building ID.
final assetsNotifierProvider = StateNotifierProvider.autoDispose.family<
    PaginatedAssetsNotifier, PaginatedAssetsState, String>((ref, buildingId) {
  final db = ref.watch(appDatabaseProvider);
  final sync = ref.watch(syncRepositoryProvider);
  return PaginatedAssetsNotifier(db, sync, buildingId);
});
