import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/initial_sync_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/common/widgets.dart';
import 'buildings_list.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const HomeScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int _currentIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Widget> _screens = const [
    BuildingsList(),
    _PlaceholderTab(title: 'Explore'),
    _PlaceholderTab(title: 'Activity'),
    _PlaceholderTab(title: 'More'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('BlockPro'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: const [OfflineIndicator()],
      ),
      drawer: _buildDrawer(context, colors, tokens),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNavBar(context, tokens, colors),
    );
  }

  Widget _buildBottomNavBar(
      BuildContext context, AppThemeTokens tokens, ColorScheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(tokens.radiusXl)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: tokens.spacingLg, vertical: tokens.spacingSm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.home_outlined, Icons.home, 'Home', colors),
              _navItem(
                  1, Icons.explore_outlined, Icons.explore, 'Explore', colors),
              _navItem(2, Icons.notifications_outlined, Icons.notifications,
                  'Activity', colors),
              _navItem(3, Icons.menu, Icons.menu, 'More', colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label,
      ColorScheme colors) {
    final isActive = _currentIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(isActive ? activeIcon : icon,
                color: isActive ? colors.primary : colors.onSurfaceVariant),
            if (isActive) ...[
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(
      BuildContext context, ColorScheme colors, AppThemeTokens tokens) {
    return Drawer(
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + tokens.spacingLg),

          // Menu items
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              context.push('/settings');
            },
          ),

          const Spacer(),
          const Divider(),

          // Sign out
          ListTile(
            leading: Icon(Icons.logout, color: colors.error),
            title: Text('Sign Out', style: TextStyle(color: colors.error)),
            onTap: () => _showSignOutConfirmation(context),
          ),
          SizedBox(height: tokens.spacingLg),
        ],
      ),
    );
  }

  Future<void> _showSignOutConfirmation(BuildContext context) async {
    final colors = context.colors;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Sign Out', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );

    if (proceed != true || !mounted) return;

    await ref.read(authRepositoryProvider).signOut();
    // Clear the cached sync check so the router redirects to /initial-sync
    // on next login (the DB was just wiped by signOut).
    ref.invalidate(needsInitialSyncProvider);
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String title;
  const _PlaceholderTab({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}
