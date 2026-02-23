import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connectivity_service.dart';

/// Singleton ConnectivityService instance.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider that emits true when the app is offline.
final isOfflineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.isOfflineStream;
});
