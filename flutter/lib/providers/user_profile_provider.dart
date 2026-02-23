import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../repositories/api_repository.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';

// FutureProvider — one-shot fetch, auto-disposes, simple reads
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  final apiRepo = ref.watch(apiRepositoryProvider);
  final data = await apiRepo.authenticatedGet('appfetchprofile',
      queryParams: {'user_id': userId});
  return UserProfile.fromJson(data['response']);
});

// StateNotifierProvider — for screens that need to update the profile
class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  UserProfileNotifier(this._apiRepository, this._userId)
      : super(const AsyncValue.loading()) {
    _loadProfile();
  }

  final ApiRepository _apiRepository;
  final String? _userId;

  Future<void> _loadProfile() async {
    if (_userId == null) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    try {
      final data = await _apiRepository.authenticatedGet('appfetchprofile',
          queryParams: {'user_id': _userId});
      final profile = UserProfile.fromJson(data['response']);
      state = AsyncValue.data(profile);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> refresh() async => await _loadProfile();
}

final userProfileNotifierProvider =
    StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  final apiRepository = ref.watch(apiRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return UserProfileNotifier(apiRepository, userId);
});

// ── ApiRepository provider ──────────────────────────────
final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final connectivityService = ref.watch(connectivityServiceProvider);
  return ApiRepository(authRepo, connectivityService);
});
