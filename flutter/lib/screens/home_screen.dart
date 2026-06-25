import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    await showRefreshProgressDialog(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BlockProAppBar(
        title: 'Blocks',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
