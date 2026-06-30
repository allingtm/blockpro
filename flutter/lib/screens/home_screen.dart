import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/initial_sync_provider.dart';
import '../widgets/common/widgets.dart';
import 'blocks_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _onRefreshPressed() async {
    final confirmed = await confirmRefreshDialog(context);
    if (confirmed != true || !mounted) return;
    // Reload in the background like app startup (per-building bars + pulsing
    // cloud) rather than a blocking progress dialog.
    ref.read(initialSyncNotifierProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    // The background initial sync owns the DB while it runs; disable manual
    // refresh until it finishes so the two can't collide.
    final isSyncing =
        ref.watch(initialSyncNotifierProvider.select((s) => s.isSyncing));
    return Scaffold(
      appBar: BlockProAppBar(
        title: 'Blocks',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The pulsing "downloading" cloud is supplied globally by
            // BlockProAppBar while syncing. Here we only hide the refresh button
            // during the sync so a manual refresh can't collide with it.
            if (!isSyncing)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh data',
                onPressed: _onRefreshPressed,
              ),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white),
              tooltip: 'About',
              onPressed: () => context.push('/about'),
            ),
          ],
        ),
      ),
      body: const BlocksListScreen(),
      floatingActionButton: const ScanFab(),
    );
  }
}
