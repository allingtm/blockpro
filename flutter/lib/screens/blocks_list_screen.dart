import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/building.dart';
import '../providers/building_badges_provider.dart';
import '../providers/buildings_provider.dart';
import '../providers/drafts_provider.dart';
import '../providers/refresh_sync_provider.dart';
import '../theme/app_palettes.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';

/// Master view: list of all blocks (buildings) the user has access to.
/// Tapping a block pushes the detail view (its inspections).
class BlocksListScreen extends ConsumerWidget {
  const BlocksListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(buildingsNotifierProvider);
    final badges = ref.watch(buildingBadgesProvider).valueOrNull ?? const {};
    final draftBuildings = ref.watch(buildingsWithDraftsProvider);
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

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(buildingsNotifierProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: state.items.length,
        itemBuilder: (context, index) {
          final building = state.items[index];
          final badge = badges[building.id] ?? const BuildingBadge();
          return _BlockCard(
            building: building,
            badge: badge,
            hasDraft: draftBuildings.contains(building.id),
            onTap: () => context.push('/block/${building.id}', extra: building),
          );
        },
      ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.building,
    required this.badge,
    required this.hasDraft,
    required this.onTap,
  });

  final Building building;
  final BuildingBadge badge;
  final bool hasDraft;
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
          Icon(Icons.apartment_rounded,
              size: 32, color: tokens.brandIcon),
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
          if (hasDraft) ...[
            const DraftChip(),
            const SizedBox(width: 8),
          ],
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
            Icon(Icons.apartment_outlined,
                size: 80, color: context.tokens.textFaint),
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
