import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/buildings_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';

class BuildingsList extends ConsumerStatefulWidget {
  const BuildingsList({super.key});

  @override
  ConsumerState<BuildingsList> createState() => _BuildingsListState();
}

class _BuildingsListState extends ConsumerState<BuildingsList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(buildingsNotifierProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(buildingsNotifierProvider);
    final tokens = context.tokens;
    final colors = context.colors;

    // First launch: no cached data, sync in progress.
    if (state.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // No data and not syncing — show empty state.
    if (state.items.isEmpty && !state.isSyncing) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacingXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.apartment_outlined,
                  size: tokens.iconXl, color: colors.onSurfaceVariant),
              SizedBox(height: tokens.spacingLg),
              Text(
                'No buildings assigned to you',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(buildingsNotifierProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(tokens.spacingLg),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Loading indicator at the bottom.
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final building = state.items[index];
          return AppCard(
            onTap: () => context.push(
              '/building/${building.id}',
              extra: building.name,
            ),
            child: Row(
              children: [
                Icon(Icons.apartment,
                    size: tokens.iconMd, color: colors.primary),
                SizedBox(width: tokens.spacingLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        building.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (building.assetCount > 0) ...[
                        SizedBox(height: tokens.spacingXs),
                        Text(
                          '${building.assetCount} asset${building.assetCount == 1 ? '' : 's'}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          );
        },
      ),
    );
  }
}
