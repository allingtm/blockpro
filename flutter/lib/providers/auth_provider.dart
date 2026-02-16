import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/bubble_auth_user.dart';
import '../repositories/auth_repository.dart';

// 1. Repository — singleton
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// 2. Auth state stream — emits on login/logout via BehaviorSubject
final authStateProvider = StreamProvider<BubbleAuthUser>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authUserStream;
});

// 3. Current user ID — derived from auth state
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.maybeWhen(
    data: (user) => user.loggedIn ? user.uid : null,
    orElse: () => null,
  );
});

// 4. Boolean convenience
final isAuthenticatedProvider = Provider<bool>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return userId != null;
});
