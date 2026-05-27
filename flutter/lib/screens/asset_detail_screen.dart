import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/asset.dart';
import '../providers/checklist_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

class AssetDetailScreen extends ConsumerStatefulWidget {
  final Asset asset;

  const AssetDetailScreen({super.key, required this.asset});

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  bool _minLoaderElapsed = false;

  @override
  void initState() {
    super.initState();
    // Show the loading state for at least 1 second so it doesn't flash.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _minLoaderElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final countAsync = ref.watch(checklistCountProvider(asset.id));
    final tokens = context.tokens;
    final colors = context.colors;

    // Show loader until both the data has arrived AND the minimum time elapsed.
    final showLoading = !_minLoaderElapsed || countAsync is AsyncLoading<int>;

    return Scaffold(
      appBar: AppBar(
        title: Text(asset.displayName),
        actions: const [OfflineIndicator()],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Asset info section ──
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.door_front_door_outlined,
                          size: tokens.iconMd, color: colors.primary),
                      SizedBox(width: tokens.spacingMd),
                      Expanded(
                        child: Text(
                          asset.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (asset.colour != null)
                        _StatusChip(colour: asset.colour!),
                    ],
                  ),
                  SizedBox(height: tokens.spacingLg),
                  if (asset.dueDate != null)
                    _InfoRow(
                      icon: asset.isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.event,
                      iconColor:
                          asset.isOverdue ? colors.error : colors.primary,
                      label: 'Due date',
                      value: _formatDate(asset.dueDate!),
                    ),
                  if (asset.lastCompleted != null) ...[
                    SizedBox(height: tokens.spacingSm),
                    _InfoRow(
                      icon: Icons.history,
                      iconColor: colors.onSurfaceVariant,
                      label: 'Last completed',
                      value: _formatDate(asset.lastCompleted!),
                    ),
                  ],
                  if (asset.frequency != null) ...[
                    SizedBox(height: tokens.spacingSm),
                    _InfoRow(
                      icon: Icons.repeat,
                      iconColor: colors.onSurfaceVariant,
                      label: 'Frequency',
                      value: asset.frequency!,
                    ),
                  ],
                  if (asset.floor != null) ...[
                    SizedBox(height: tokens.spacingSm),
                    _InfoRow(
                      icon: Icons.layers_outlined,
                      iconColor: colors.onSurfaceVariant,
                      label: 'Floor',
                      value: asset.floor!,
                    ),
                  ],
                  if (asset.location != null) ...[
                    SizedBox(height: tokens.spacingSm),
                    _InfoRow(
                      icon: Icons.place_outlined,
                      iconColor: colors.onSurfaceVariant,
                      label: 'Location',
                      value: asset.location!,
                    ),
                  ],
                ],
              ),
            ),

            // ── Help / tooltip section ──
            if (asset.tooltipText != null ||
                asset.tooltipUrlList.isNotEmpty) ...[
              SizedBox(height: tokens.spacingLg),
              _HelpSection(asset: asset),
            ],

            SizedBox(height: tokens.spacingXl),

            // ── Start inspection button ──
            if (showLoading)
              const AppButton(
                text: 'Preparing checklist...',
                isLoading: true,
              )
            else
              countAsync.when(
                loading: () => const AppButton(
                  text: 'Preparing checklist...',
                  isLoading: true,
                ),
                error: (error, _) => AppButton(
                  text: 'Retry loading checklist',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.outline,
                  onPressed: () =>
                      ref.invalidate(checklistCountProvider(asset.id)),
                ),
                data: (count) => AppButton(
                  text: count == 0
                      ? 'No checklist questions'
                      : 'Start Inspection ($count questions)',
                  icon: Icons.play_arrow,
                  onPressed: count == 0
                      ? null
                      : () => context.push(
                            '/inspection/${asset.id}',
                            extra: asset.displayName,
                          ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small coloured pill showing the asset's Red/Yellow/Green status.
class _StatusChip extends StatelessWidget {
  final AssetColour colour;
  const _StatusChip({required this.colour});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (colour) {
      AssetColour.red => Theme.of(context).colorScheme.error,
      AssetColour.yellow => const Color(0xFFD89D2A),
      AssetColour.green => Theme.of(context).colorScheme.tertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        colour.displayText,
        style: TextStyle(
          color: statusColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Expandable help section showing `tooltiptext` and `tooltipurls` from the API.
class _HelpSection extends StatelessWidget {
  final Asset asset;
  const _HelpSection({required this.asset});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;
    final urls = asset.tooltipUrlList;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline,
                  size: tokens.iconSm, color: colors.primary),
              SizedBox(width: tokens.spacingSm),
              Text(
                'Help',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          if (asset.tooltipText != null) ...[
            SizedBox(height: tokens.spacingSm),
            Text(
              asset.tooltipText!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (urls.isNotEmpty) ...[
            SizedBox(height: tokens.spacingSm),
            ...urls.map((url) => Padding(
                  padding: EdgeInsets.only(top: tokens.spacingXs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.link, size: 14, color: colors.primary),
                      SizedBox(width: tokens.spacingXs),
                      Expanded(
                        child: SelectableText(
                          url,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.primary),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
