import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local app/chat lock: biometrics first, then a PIN stored on-device.
class AppLock {
  static const enabledKey = 'app_lock_enabled';
  static const pinKey = 'app_lock_pin_hash';
  static const timeoutKey = 'app_lock_timeout_seconds';

  static final enabled = ValueNotifier<bool>(false);
  static const _secure = FlutterSecureStorage();
  static const _kdfIterations = 120000;
  static const _keyLength = 32;

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

  static Future<bool> hasPin() async =>
      (await _secure.read(key: pinKey))?.isNotEmpty == true ||
      ((await _prefs).getString(pinKey)?.isNotEmpty ?? false);

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String value) {
    final bytes = <int>[];
    for (var i = 0; i + 1 < value.length; i += 2) {
      bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Salted PBKDF2-HMAC-SHA256 hash. [salt] is a hex-encoded 16-byte value.
  static String hashPin(String pin, {required String salt}) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(_fromHex(salt), _kdfIterations, _keyLength));
    return _hex(derivator.process(utf8.encode(pin)));
  }

  /// Fast legacy hash kept only to migrate existing installations.
  static String legacyHashPin(String pin) {
    final bytes = utf8.encode('bro.lock.v1|$pin');
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final byte in bytes) {
      hash ^= BigInt.from(byte);
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16);
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var different = 0;
    for (var i = 0; i < a.length; i++) {
      different |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return different == 0;
  }

  static Future<void> setPin(String pin) async {
    final salt = _hex(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    await _secure.write(
      key: pinKey,
      value: 'v2:$salt:${hashPin(pin, salt: salt)}',
    );
    // Remove the reversible legacy hash once migration has succeeded.
    await (await _prefs).remove(pinKey);
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _secure.read(key: pinKey);
    if (stored != null && stored.isNotEmpty) {
      final parts = stored.split(':');
      if (parts.length == 3 && parts.first == 'v2') {
        return _same(parts[2], hashPin(pin, salt: parts[1]));
      }
      return false;
    }
    final legacy = (await _prefs).getString(pinKey);
    if (legacy == null || legacy.isEmpty) return false;
    if (_same(legacy, legacyHashPin(pin))) {
      await setPin(pin);
      return true;
    }
    return false;
  }

  static Future<int> timeoutSeconds() async =>
      (await _prefs).getInt(timeoutKey) ?? 60; // Default to 1 minute to match settings

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
}
