import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rxdart/rxdart.dart';

/// Combines hardware connectivity (connectivity_plus) with API call
/// success/failure signals to determine if the app is effectively offline.
class ConnectivityService {
  ConnectivityService() {
    _init();
  }

  final _connectivity = Connectivity();

  /// Hardware-level: does the device have any network interface?
  final _hasNetworkSubject = BehaviorSubject<bool>.seeded(true);

  /// API-level: has the most recent API call succeeded?
  final _apiReachableSubject = BehaviorSubject<bool>.seeded(true);

  /// Combined stream: true when the app is offline.
  late final Stream<bool> isOfflineStream;

  void _init() {
    // Listen to hardware connectivity changes
    _connectivity.onConnectivityChanged.listen((results) {
      final hasNetwork =
          results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
      _hasNetworkSubject.add(hasNetwork);
    });

    // Check initial state
    _connectivity.checkConnectivity().then((results) {
      final hasNetwork =
          results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
      _hasNetworkSubject.add(hasNetwork);
    });

    // Offline if no network OR API unreachable.
    // debounceTime prevents flicker from transient state changes.
    isOfflineStream = Rx.combineLatest2<bool, bool, bool>(
      _hasNetworkSubject.stream,
      _apiReachableSubject.stream,
      (hasNetwork, apiReachable) => !hasNetwork || !apiReachable,
    ).distinct().debounceTime(const Duration(seconds: 1));
  }

  /// Called by ApiRepository when an API call succeeds.
  void reportApiSuccess() {
    _apiReachableSubject.add(true);
  }

  /// Called by ApiRepository when an API call fails with a network error.
  void reportApiFailure() {
    _apiReachableSubject.add(false);
  }

  void dispose() {
    _hasNetworkSubject.close();
    _apiReachableSubject.close();
  }
}
