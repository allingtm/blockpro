import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/asset.dart';
import '../models/building.dart';
import '../models/outbox_entry.dart';
import '../providers/assets_provider.dart';
import '../providers/building_badges_provider.dart';
import '../providers/drafts_provider.dart';
import '../providers/outbox_drain_provider.dart';
import '../providers/outbox_provider.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/asset_status.dart';
import '../utils/date_format.dart';
import '../widgets/common/widgets.dart';

/// Detail view: inspections (assets) for a single block.
/// Pushed from [BlocksListScreen] via /block/:id.
class BlockInspectionsScreen extends ConsumerStatefulWidget {
  const BlockInspectionsScreen({super.key, required this.building});

  final Building building;

  @override
  ConsumerState<BlockInspectionsScreen> createState() =>
      _BlockInspectionsScreenState();
}

class _BlockInspectionsScreenState
    extends ConsumerState<BlockInspectionsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref
          .read(assetsNotifierProvider(widget.building.id).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(assetsNotifierProvider(widget.building.id));
    final badge = (ref.watch(buildingBadgesProvider).valueOrNull ??
            const <String, BuildingBadge>{})[widget.building.id] ??
        const BuildingBadge();

    return Scaffold(
      appBar: BlockProAppBar(
        title: widget.building.name,
        badgeCount: badge.red,
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(PaginatedAssetsState state) {
    if (state.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty && !state.isSyncing) {
      return const _NoInspectionsMessage();
    }

    final query = _query.trim();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: AppTextField(
            controller: _searchController,
            hint: 'Search inspections…',
            prefixIcon: Icons.search,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        Expanded(
          child: query.isEmpty
              ? _buildPaginatedList(state)
              : _buildSearchResults(query),
        ),
      ],
    );
  }

  Widget _buildPaginatedList(PaginatedAssetsState state) {
    return RefreshIndicator(
      onRefresh: () => ref
          .read(assetsNotifierProvider(widget.building.id).notifier)
          .refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final asset = state.items[index];
          return _InspectionCard(asset: asset);
        },
      ),
    );
  }

  Widget _buildSearchResults(String query) {
    final results = ref
            .watch(assetSearchResultsProvider(
              (buildingId: widget.building.id, query: query),
            ))
            .valueOrNull ??
        const <Asset>[];
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No inspections match',
            style: TextStyle(fontSize: 16, color: context.tokens.textFaint),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: results.length,
      itemBuilder: (context, index) => _InspectionCard(asset: results[index]),
    );
  }
}

class _InspectionCard extends ConsumerWidget {
  const _InspectionCard({required this.asset});
  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outboxStatus = ref.watch(assetOutboxStatusProvider)[asset.id];
    // A queued completion keeps the card green even after a cache wipe has reset
    // the asset's optimistic due-date (the status is derived from the durable
    // outbox, not the wipeable asset row).
    final status =
        outboxStatus != null ? AssetStatus.green : assetStatusFor(asset);
    final stripe = colourForStatus(status);
    final tokens = context.tokens;
    final hasDraft = (ref.watch(assetDraftsProvider).valueOrNull ??
            const <String>{})
        .contains(asset.id);

    return StripedCard(
      stripeColor: stripe,
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      onTap: () => context.push(
        '/inspection/${asset.id}',
        extra: asset,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        asset.displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: tokens.textStrong,
                        ),
                      ),
                    ),
                    if (hasDraft) ...[
                      const SizedBox(width: 8),
                      const DraftChip(),
                    ],
                    if (outboxStatus != null) ...[
                      const SizedBox(width: 8),
                      OutboxStatusChip(
                        status: outboxStatus,
                        onTap: _retryHandler(context, ref, outboxStatus),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                if (asset.lastCompleted != null)
                  _MetaLine(
                    label: 'Last completed',
                    value: formatOrdinalDate(asset.lastCompleted!),
                  ),
                if (asset.frequency != null) ...[
                  const SizedBox(height: 4),
                  _MetaLine(label: 'Frequency', value: asset.frequency!),
                ],
                if (asset.dueDate != null) ...[
                  const SizedBox(height: 4),
                  _MetaLine(
                    label: 'Next due by',
                    value: formatOrdinalDate(asset.dueDate!),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: tokens.textFaint),
        ],
      ),
    );
  }

  /// Tap action for the outbox chip: `failed` retries immediately, `needsReview`
  /// confirms first (it may already have reached the server), the rest are inert.
  VoidCallback? _retryHandler(
      BuildContext context, WidgetRef ref, OutboxStatus status) {
    switch (status) {
      case OutboxStatus.failed:
        return () => _retry(ref);
      case OutboxStatus.needsReview:
        return () => _confirmAndRetry(context, ref);
      case OutboxStatus.pending:
      case OutboxStatus.sending:
        return null;
    }
  }

  Future<void> _retry(WidgetRef ref) async {
    final entry = ref.read(assetQueuedEntryProvider(asset.id));
    if (entry == null) return;
    await ref.read(outboxStoreProvider).mutate(
          entry.submissionId,
          (e) => e.copyWith(status: OutboxStatus.pending, clearError: true),
        );
    ref.read(outboxEntriesProvider.notifier).refresh();
    unawaited(ref.read(outboxDrainerProvider).drain());
  }

  Future<void> _confirmAndRetry(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-send inspection?'),
        content: const Text(
          'This inspection may already have been submitted. Re-send it anyway?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Re-send')),
        ],
      ),
    );
    if (ok == true) await _retry(ref);
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 14,
          color: tokens.textStrong,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: tokens.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NoInspectionsMessage extends StatelessWidget {
  const _NoInspectionsMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 80, color: context.tokens.textFaint),
            const SizedBox(height: 16),
            const Text(
              'No inspections for this block',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
