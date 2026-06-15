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

/// Hardware-only connectivity — true when the device has any network interface.
/// Distinct from [isOfflineProvider] (which also factors in API reachability):
/// the outbox drainer uses this so a stale "API unreachable" flag can't stop it
/// from probing once the network is back.
final hasNetworkProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.hasNetworkStream;
});
