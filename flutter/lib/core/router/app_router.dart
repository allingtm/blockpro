import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/welcome_screen.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);

  return GoRouter(
    redirect: (context, state) {
      final isAuth = isAuthenticated;
      final location = state.matchedLocation;

      final isGoingToAuth = location == '/login' || location == '/';

      // Default: authenticated → /home, unauthenticated → /
      if (location == '' || location == '/') {
        return isAuth ? '/home' : '/';
      }

      // Redirect to login for protected routes when not authenticated
      if (!isAuth && !isGoingToAuth) return '/login';

      // Redirect authenticated users away from auth pages
      if (isAuth && isGoingToAuth && location != '/') return '/home';

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
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
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
