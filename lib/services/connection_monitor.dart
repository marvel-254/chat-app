import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks the device's network connectivity and publishes a debounced
/// online state consumed by the offline banner in the app scaffold.
class ConnectionMonitor {
  ConnectionMonitor._();

  static const Duration _debounceDuration = Duration(seconds: 3);

  /// Whether the device currently appears online; defaults to true.
  static final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static Timer? _debounce;

  /// Starts listening for connectivity changes. Safe to call repeatedly.
  static void start() {
    if (_subscription != null) return;
    _subscription =
        Connectivity().onConnectivityChanged.listen(_handleConnectivityChange);
    unawaited(_reconcileNow());
  }

  /// Stops listening and resets the online state.
  static Future<void> dispose() async {
    final subscription = _subscription;
    _subscription = null;
    _debounce?.cancel();
    _debounce = null;
    isOnline.value = true;
    await subscription?.cancel();
  }

  static Future<void> _reconcileNow() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _handleConnectivityChange(results);
    } catch (error) {
      debugPrint('Connectivity check failed: $error');
    }
  }

  static void _handleConnectivityChange(List<ConnectivityResult> results) {
    final online = results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );
    if (online == isOnline.value) {
      _debounce?.cancel();
      _debounce = null;
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () => isOnline.value = online);
  }
}
