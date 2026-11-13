import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local app/chat lock: biometrics first, then a PIN stored on-device.
class AppLock {
  static const enabledKey = 'app_lock_enabled';
  static const pinKey = 'app_lock_pin_hash';
  static const timeoutKey = 'app_lock_timeout_seconds';

  static final enabled = ValueNotifier<bool>(false);

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  static Future<void> bootstrap() async {
    enabled.value = (await _prefs).getBool(enabledKey) ?? false;
  }

  static Future<bool> isEnabled() async =>
      (await _prefs).getBool(enabledKey) ?? false;

  static Future<void> setEnabled(bool value) async {
    await (await _prefs).setBool(enabledKey, value);
    enabled.value = value;
  }

  static Future<bool> hasPin() async {
    final pin = (await _prefs).getString(pinKey);
    return pin != null && pin.isNotEmpty;
  }

  static Future<void> setPin(String pin) async =>
      (await _prefs).setString(pinKey, hashPin(pin));

  static Future<bool> verifyPin(String pin) async {
    final stored = (await _prefs).getString(pinKey);
    if (stored == null || stored.isEmpty) return false;
    return stored == hashPin(pin);
  }

  static Future<int> timeoutSeconds() async =>
      (await _prefs).getInt(timeoutKey) ?? 15;

  static Future<void> setTimeoutSeconds(int seconds) async =>
      (await _prefs).setInt(timeoutKey, seconds);

  /// Try OS biometrics / device credentials. Returns false if unavailable
  /// or the user cancels — caller should fall back to the PIN pad.
  static Future<bool> authenticate({required String reason}) async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      if (!supported) return false;
      return await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static String hashPin(String pin) {
    final bytes = utf8.encode('bro.lock.v1|$pin');
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}
