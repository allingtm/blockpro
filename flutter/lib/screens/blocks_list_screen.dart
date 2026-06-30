import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/building.dart';
import '../models/outbox_entry.dart';
import '../providers/building_badges_provider.dart';
import '../providers/buildings_provider.dart';
import '../providers/drafts_provider.dart';
import '../providers/initial_sync_provider.dart';
import '../providers/outbox_provider.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';

/// Master view: list of all blocks (buildings) the user has access to.
/// Tapping a block pushes the detail view (its inspections).
class BlocksListScreen extends ConsumerStatefulWidget {
  const BlocksListScreen({super.key});

  @override
  ConsumerState<BlocksListScreen> createState() => _BlocksListScreenState();
}

class _BlocksListScreenState extends ConsumerState<BlocksListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    // Seed from the provider so the box and the active query stay in sync when
    // the user returns here (the screen stays mounted beneath pushed routes).
    _searchController = TextEditingController(
      text: ref.read(buildingSearchQueryProvider),
    );

    // On first launch (empty DB), kick off the full background sync that
    // populates this list. The list itself renders from the DB-watch as rows
    // land; this just drives the download + the inline progress bar. Returning
    // users (DB already populated) skip it and see cached data immediately.
    Future.microtask(() async {
      try {
        final needsSync = await ref.read(needsInitialSyncProvider.future);
        if (needsSync && mounted) {
          ref.read(initialSyncNotifierProvider.notifier).runSync();
        }
      } catch (_) {
        // countBuildings() failed; leave the list to its own loading state.
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(buildingSearchQueryProvider.notifier).state = value;
    // Refresh the clear-icon visibility.
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(buildingSearchQueryProvider.notifier).state = '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(buildingsNotifierProvider);
    final sync = ref.watch(initialSyncNotifierProvider);

    // The inline progress bar is intentionally minimal, so surface a
    // background-sync failure as a retryable SnackBar.
    ref.listen(initialSyncNotifierProvider, (prev, next) {
      if (next.hasError && !(prev?.hasError ?? false) && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(next.error!),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () =>
                  ref.read(initialSyncNotifierProvider.notifier).retry(),
            ),
          ));
      }
    });

    // No rows yet: show a spinner while the background sync is still running (or
    // still deciding whether to run). Only fall through to the genuine empty
    // state once the sync has settled, so it can't flash during the startup
    // async gaps or an error. A manual refresh wipes the DB then re-downloads via
    // the same flow, so this naturally covers the refresh's empty window too.
    if (state.items.isEmpty && !sync.isSettled) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.items.isEmpty) {
      return _EmptyState(
        // Reload everything in the background (wipe + re-download), same as
        // startup — no progress dialog.
        onReload: () =>
            ref.read(initialSyncNotifierProvider.notifier).refresh(),
      );
    }

    final badges = ref.watch(buildingBadgesProvider).valueOrNull ?? const {};
    final draftBuildings = ref.watch(buildingsWithDraftsProvider);
    final queuedBuildings = ref.watch(buildingsWithQueuedProvider);
    final withAssets = ref.watch(buildingsWithAssetsProvider);
    final query = ref.watch(buildingSearchQueryProvider).trim();

    // A row is ready (badge shown, tappable) once its own assets have landed in
    // SQLite (`withAssets`), so its red/amber badge is accurate. Returning users
    // (`!started`), a settled/errored sync, and the end of the assets phase all
    // resolve everything so no row loads forever. NB: we deliberately do *not*
    // use `b.assetCount` — that comes from `app_fetchbuildings`, whose asset-list
    // field isn't populated, so it's 0 for every building and would mark all rows
    // ready instantly (no loading bar at all).
    bool buildingReady(Building b) =>
        !sync.started ||
        sync.isSettled ||
        sync.assetsPhaseDone ||
        withAssets.contains(b.id);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: AppTextField(
            controller: _searchController,
            hint: 'Search buildings…',
            prefixIcon: Icons.search,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearSearch,
                  ),
          ),
        ),
        Expanded(
          child: query.isEmpty
              ? _buildPaginatedList(
                  state.items,
                  badges,
                  draftBuildings,
                  queuedBuildings,
                  buildingReady,
                )
              : _buildSearchResults(
                  badges,
                  draftBuildings,
                  queuedBuildings,
                  buildingReady,
                ),
        ),
      ],
    );
  }

  Widget _buildPaginatedList(
    List<Building> items,
    Map<String, BuildingBadge> badges,
    Set<String> draftBuildings,
    Set<String> queuedBuildings,
    bool Function(Building) buildingReady,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        // Don't collide with the background initial sync (it's already
        // repopulating the DB and owns the buildings fetch).
        if (ref.read(initialSyncNotifierProvider).isSyncing) return;
        await ref.read(buildingsNotifierProvider.notifier).refresh();
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: items.length,
        itemBuilder: (context, index) => _buildCard(
            items[index], badges, draftBuildings, queuedBuildings, buildingReady),
      ),
    );
  }

  Widget _buildSearchResults(
    Map<String, BuildingBadge> badges,
    Set<String> draftBuildings,
    Set<String> queuedBuildings,
    bool Function(Building) buildingReady,
  ) {
    final results =
        ref.watch(buildingSearchResultsProvider).valueOrNull ?? const [];
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No buildings match',
            style: TextStyle(fontSize: 16, color: context.tokens.textFaint),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: results.length,
      itemBuilder: (context, index) => _buildCard(
          results[index], badges, draftBuildings, queuedBuildings, buildingReady),
    );
  }

  Widget _buildCard(
    Building building,
    Map<String, BuildingBadge> badges,
    Set<String> draftBuildings,
    Set<String> queuedBuildings,
    bool Function(Building) buildingReady,
  ) {
    final badge = badges[building.id] ?? const BuildingBadge();
    final ready = buildingReady(building);
    return _BlockCard(
      building: building,
      badge: badge,
      hasDraft: draftBuildings.contains(building.id),
      hasQueued: queuedBuildings.contains(building.id),
      ready: ready,
      onTap: ready
          ? () => context.push('/block/${building.id}', extra: building)
          : null,
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.building,
    required this.badge,
    required this.hasDraft,
    required this.hasQueued,
    required this.ready,
    required this.onTap,
  });

  final Building building;
  final BuildingBadge badge;
  final bool hasDraft;
  final bool hasQueued;

  /// False until this building's assets have downloaded. While false the card
  /// hides its badge/chevron, shows an indeterminate loading bar along the
  /// bottom, and its tap is disabled.
  final bool ready;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Neutral stripe while loading so the green "all clear" colour doesn't show
    // before the badge data is in.
    final stripe = ready ? _stripeColour(badge) : tokens.textFaint;
    return StripedCard(
      stripeColor: stripe,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.apartment_rounded, size: 32, color: tokens.brandIcon),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  building.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tokens.textStrong,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasQueued) ...[
                const OutboxStatusChip(status: OutboxStatus.pending),
                const SizedBox(width: 8),
              ],
              if (hasDraft) ...[const DraftChip(), const SizedBox(width: 8)],
              // Badge + chevron appear only once the building's data is loaded.
              if (ready) ...[
                _BadgeIndicator(badge: badge),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: tokens.textFaint),
              ],
            ],
          ),
          // Indeterminate loading bar along the bottom while this building's
          // assets are still downloading.
          if (!ready) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ],
      ),
    );
  }

  static Color _stripeColour(BuildingBadge badge) {
    if (badge.red > 0) return kStatusRed;
    if (badge.amber > 0) return kStatusAmber;
    return kStatusGreen;
  }
}

class _BadgeIndicator extends StatelessWidget {
  const _BadgeIndicator({required this.badge});
  final BuildingBadge badge;

  @override
  Widget build(BuildContext context) {
    if (!badge.hasAny) {
      return const Icon(Icons.check_circle, color: kStatusGreen, size: 24);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge.red > 0) _Pill(count: badge.red, color: kStatusRed),
        if (badge.red > 0 && badge.amber > 0) const SizedBox(width: 6),
        if (badge.amber > 0) _Pill(count: badge.amber, color: kStatusAmber),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.apartment_outlined,
              size: 80,
              color: context.tokens.textFaint,
            ),
            const SizedBox(height: 16),
            const Text(
              'No data loaded',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Load data',
              icon: Icons.refresh,
              fullWidth: false,
              onPressed: onReload,
            ),
          ],
        ),
      ),
    );
  }
}
