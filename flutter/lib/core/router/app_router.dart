import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/asset.dart';
import '../../models/building.dart';
import '../../providers/auth_provider.dart';
import '../../providers/initial_sync_provider.dart';
import '../../screens/about_screen.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/block_inspections_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/initial_sync_screen.dart';
import '../../screens/inspection_screen.dart';
import '../../screens/qr_scan_screen.dart';
import '../../screens/welcome_screen.dart';

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

      debugPrint(
        '── ROUTER REDIRECT ── location=$location '
        'isAuth=$isAuth needsSync=$needsSync '
        'syncAsync=$syncAsync',
      );

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
        path: '/block/:id',
        name: 'block',
        pageBuilder: (context, state) {
          final building = state.extra as Building;
          return _slidePage(state, BlockInspectionsScreen(building: building));
        },
      ),
      GoRoute(
        path: '/inspection/:id',
        name: 'inspection',
        pageBuilder: (context, state) {
          final asset = state.extra as Asset;
          return _slidePage(state, InspectionScreen(asset: asset));
        },
      ),
      GoRoute(
        path: '/scan',
        name: 'scan',
        pageBuilder: (context, state) =>
            _slidePage(state, const QrScanScreen()),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        pageBuilder: (context, state) => _slidePage(state, const AboutScreen()),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.matchedLocation}')),
    ),
  );
});

/// Page that slides in from the right when pushed and back out to the right
/// when popped (right-to-left forward navigation, reversed on return).
CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));
      return SlideTransition(position: slide, child: child);
    },
  );
}
