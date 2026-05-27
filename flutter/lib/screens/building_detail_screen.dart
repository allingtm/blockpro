import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/asset.dart';
import '../providers/assets_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

class BuildingDetailScreen extends ConsumerStatefulWidget {
  final String buildingId;
  final String buildingName;

  const BuildingDetailScreen({
    super.key,
    required this.buildingId,
    required this.buildingName,
  });

  @override
  ConsumerState<BuildingDetailScreen> createState() =>
      _BuildingDetailScreenState();
}

class _BuildingDetailScreenState extends ConsumerState<BuildingDetailScreen> {
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
      ref
          .read(assetsNotifierProvider(widget.buildingId).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assetsNotifierProvider(widget.buildingId));
    final tokens = context.tokens;
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.buildingName),
        actions: const [OfflineIndicator()],
      ),
      body: _buildBody(state, tokens, colors),
    );
  }

  Widget _buildBody(
      PaginatedAssetsState state, AppThemeTokens tokens, ColorScheme colors) {
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
              Icon(Icons.inventory_2_outlined,
                  size: tokens.iconXl, color: colors.onSurfaceVariant),
              SizedBox(height: tokens.spacingLg),
              Text(
                'No assets found for this building',
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
      onRefresh: () => ref
          .read(assetsNotifierProvider(widget.buildingId).notifier)
          .refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.all(tokens.spacingLg),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          final asset = state.items[index];
          return _AssetCard(asset: asset);
        },
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  final Asset asset;
  const _AssetCard({required this.asset});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;
    final statusColor = _colourFor(asset.colour, colors);
    final statusIcon = switch (asset.colour) {
      AssetColour.red => Icons.warning_amber_rounded,
      AssetColour.yellow => Icons.schedule,
      AssetColour.green => Icons.check_circle,
      null => Icons.circle_outlined,
    };

    return AppCard(
      onTap: () => context.push('/asset/${asset.id}', extra: asset),
      child: Row(
        children: [
          Icon(Icons.door_front_door_outlined,
              size: tokens.iconMd, color: colors.primary),
          SizedBox(width: tokens.spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.displayName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (asset.dueDate != null) ...[
                  SizedBox(height: tokens.spacingXs),
                  Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      SizedBox(width: tokens.spacingXs),
                      Text(
                        asset.isOverdue
                            ? 'Overdue — was ${_formatDate(asset.dueDate!)}'
                            : 'Next: ${_formatDate(asset.dueDate!)}',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: statusColor,
                                ),
                      ),
                    ],
                  ),
                ],
                if (asset.location != null || asset.floor != null) ...[
                  SizedBox(height: tokens.spacingXs),
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 14, color: colors.onSurfaceVariant),
                      SizedBox(width: tokens.spacingXs),
                      Expanded(
                        child: Text(
                          _locationLine(asset),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }

  static String _locationLine(Asset asset) {
    final parts = <String>[
      if (asset.floor != null) 'Floor ${asset.floor!}',
      if (asset.location != null) asset.location!,
    ];
    return parts.join(' · ');
  }
}

Color _colourFor(AssetColour? colour, ColorScheme colors) {
  return switch (colour) {
    AssetColour.red => colors.error,
    AssetColour.yellow => const Color(0xFFD89D2A),
    AssetColour.green => colors.tertiary,
    null => colors.onSurfaceVariant,
  };
}
