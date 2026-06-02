import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_palettes.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';
import 'about_screen.dart';
import 'blocks_list_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tabIndex = 0;

  Future<void> _onRefreshPressed() async {
    final confirmed = await confirmRefreshDialog(context);
    if (confirmed != true || !mounted) return;
    await showRefreshProgressDialog(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final title = _tabIndex == 0 ? 'Blocks' : 'About';
    return Scaffold(
      appBar: BlockProAppBar(
        title: title,
        trailing: _tabIndex == 0
            ? IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh data',
                onPressed: _onRefreshPressed,
              )
            : null,
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          BlocksListScreen(),
          AboutScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: context.tokens.cardSurface,
        indicatorColor: kActionBlue.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.apartment_outlined),
            selectedIcon: Icon(Icons.apartment, color: kActionBlue),
            label: 'Blocks',
          ),
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info, color: kActionBlue),
            label: 'About',
          ),
        ],
      ),
    );
  }
}
