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

  /// Hardware-only connectivity stream — true when the device has any network
  /// interface, regardless of whether the API has been reached. The outbox
  /// drainer keys off this (the drain itself is the API probe), so it isn't
  /// blocked by a stale [_apiReachableSubject].
  Stream<bool> get hasNetworkStream => _hasNetworkSubject.stream.distinct();

  void _init() {
    // Listen to hardware connectivity changes.
    _connectivity.onConnectivityChanged.listen(_updateNetwork);

    // Check initial state.
    _connectivity.checkConnectivity().then(_updateNetwork);

    // Offline if no network OR API unreachable.
    // debounceTime prevents flicker from transient state changes.
    isOfflineStream = Rx.combineLatest2<bool, bool, bool>(
      _hasNetworkSubject.stream,
      _apiReachableSubject.stream,
      (hasNetwork, apiReachable) => !hasNetwork || !apiReachable,
    ).distinct().debounceTime(const Duration(seconds: 1));
  }

  void _updateNetwork(List<ConnectivityResult> results) {
    final hasNetwork =
        results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
    _hasNetworkSubject.add(hasNetwork);
    if (hasNetwork) {
      // Hardware connectivity (re)gained — give the API the benefit of the doubt
      // so the app flips back online and retries. A subsequent failed call will
      // reset this to false. Without this, [_apiReachableSubject] stays stuck
      // false after going offline (it only clears on a *successful* call), so
      // the app would never detect it's back online — a deadlock, since nothing
      // calls the API until the app believes it's online.
      _apiReachableSubject.add(true);
    }
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
