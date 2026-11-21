import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Tracks the device's network connectivity and publishes a debounced
/// online state consumed by the offline banner in the app scaffold.
class ConnectionMonitor {
  ConnectionMonitor._();

  static const Duration _debounceDuration = Duration(seconds: 3);
  static const String _probeUrl = String.fromEnvironment('SUPABASE_URL',
      defaultValue: 'https://supabase.co');

  static bool _checking = false;

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
    final hasInterface = results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(_applyOnlineState(hasInterface));
    });
  }

  static Future<void> _applyOnlineState(bool hasInterface) async {
    if (!hasInterface) {
      isOnline.value = false;
      return;
    }
    final reachable = await _isReachable();
    if (isOnline.value != reachable) isOnline.value = reachable;
  }

  /// A connected interface is not proof of internet access. This probe accepts
  /// any HTTP response, including 401 from Supabase, as evidence of reachability.
  static Future<bool> _isReachable() async {
    if (_checking) return isOnline.value;
    _checking = true;
    final client = http.Client();
    try {
      final uri = Uri.tryParse(_probeUrl);
      final host = uri?.host ?? 'supabase.co';
      await client
          .get(Uri.https(host, '/rest/v1/'))
          .timeout(const Duration(seconds: 6));
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
      _checking = false;
    }
  }
}
