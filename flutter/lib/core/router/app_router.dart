import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/initial_sync_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/initial_sync_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/asset_detail_screen.dart';
import '../../screens/building_detail_screen.dart';
import '../../screens/inspection_screen.dart';
import '../../screens/welcome_screen.dart';
import '../../models/asset.dart';

/// Notifier that triggers GoRouter refreshes when auth or sync state changes.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(isAuthenticatedProvider, (prev, next) => notifyListeners());
    ref.listen(needsInitialSyncProvider, (prev, next) => notifyListeners());
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final isAuth = ref.read(isAuthenticatedProvider);
      final syncAsync = ref.read(needsInitialSyncProvider);
      final needsSync = syncAsync.valueOrNull ?? true;
      final location = state.matchedLocation;

      debugPrint('── ROUTER REDIRECT ── location=$location '
          'isAuth=$isAuth needsSync=$needsSync '
          'syncAsync=$syncAsync');

      final isGoingToAuth = location == '/login' || location == '/';

      // Default: authenticated → /home or /initial-sync, unauthenticated → /
      if (location == '' || location == '/') {
        if (!isAuth) return '/';
        return needsSync ? '/initial-sync' : '/home';
      }

      // Redirect to login for protected routes when not authenticated
      if (!isAuth && !isGoingToAuth) return '/login';

      // Redirect authenticated users away from auth pages
      if (isAuth && isGoingToAuth && location != '/') {
        return needsSync ? '/initial-sync' : '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/initial-sync',
        name: 'initial-sync',
        builder: (context, state) => const InitialSyncScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/building/:id',
        name: 'building',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final name = state.extra as String? ?? 'Building';
          return BuildingDetailScreen(buildingId: id, buildingName: name);
        },
      ),
      GoRoute(
        path: '/asset/:id',
        name: 'asset',
        builder: (context, state) {
          final asset = state.extra as Asset;
          return AssetDetailScreen(asset: asset);
        },
      ),
      GoRoute(
        path: '/inspection/:id',
        name: 'inspection',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final name = state.extra as String? ?? 'Inspection';
          return InspectionScreen(assetId: id, assetName: name);
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
          child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});
