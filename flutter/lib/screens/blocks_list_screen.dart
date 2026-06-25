import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/building.dart';
import '../models/outbox_entry.dart';
import '../providers/building_badges_provider.dart';
import '../providers/buildings_provider.dart';
import '../providers/drafts_provider.dart';
import '../providers/outbox_provider.dart';
import '../providers/refresh_sync_provider.dart';
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
    final isRefreshing = ref.watch(
      refreshNotifierProvider.select((s) => s.isRunning),
    );

    // While a manual refresh is running, the DB is being wiped and
    // repopulated row-by-row. Show a stable placeholder behind the progress
    // dialog rather than letting the list flicker empty and fill in live.
    if (isRefreshing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty && !state.isSyncing) {
      return _EmptyState(
        // From the empty state the user is explicitly loading data, so skip
        // the refresh confirmation and go straight to the progress dialog.
        onReload: () => showRefreshProgressDialog(context, ref),
      );
    }

    final badges = ref.watch(buildingBadgesProvider).valueOrNull ?? const {};
    final draftBuildings = ref.watch(buildingsWithDraftsProvider);
    final queuedBuildings = ref.watch(buildingsWithQueuedProvider);
    final query = ref.watch(buildingSearchQueryProvider).trim();

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
                )
              : _buildSearchResults(badges, draftBuildings, queuedBuildings),
        ),
      ],
    );
  }

  Widget _buildPaginatedList(
    List<Building> items,
    Map<String, BuildingBadge> badges,
    Set<String> draftBuildings,
    Set<String> queuedBuildings,
  ) {
    return RefreshIndicator(
      onRefresh: () => ref.read(buildingsNotifierProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            _buildCard(items[index], badges, draftBuildings, queuedBuildings),
      ),
    );
  }

  Widget _buildSearchResults(
    Map<String, BuildingBadge> badges,
    Set<String> draftBuildings,
    Set<String> queuedBuildings,
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
      itemBuilder: (context, index) =>
          _buildCard(results[index], badges, draftBuildings, queuedBuildings),
    );
  }

  Widget _buildCard(
    Building building,
    Map<String, BuildingBadge> badges,
    Set<String> draftBuildings,
    Set<String> queuedBuildings,
  ) {
    final badge = badges[building.id] ?? const BuildingBadge();
    return _BlockCard(
      building: building,
      badge: badge,
      hasDraft: draftBuildings.contains(building.id),
      hasQueued: queuedBuildings.contains(building.id),
      onTap: () => context.push('/block/${building.id}', extra: building),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.building,
    required this.badge,
    required this.hasDraft,
    required this.hasQueued,
    required this.onTap,
  });

  final Building building;
  final BuildingBadge badge;
  final bool hasDraft;
  final bool hasQueued;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final stripe = _stripeColour(badge);
    return StripedCard(
      stripeColor: stripe,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      onTap: onTap,
      child: Row(
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
          _BadgeIndicator(badge: badge),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: tokens.textFaint),
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
