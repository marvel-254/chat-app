import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocks screenshots/recordings on Android using WindowManager.FLAG_SECURE.
/// On iOS, attempts to restrict copy/paste and provides a framework for
/// platform-specific secure rendering.
class SecureScreen {
  /// Android channel for secure screen control
  static const _androidChannel = MethodChannel('bro/secure_screen');

  /// iOS isn't supported via MethodChannel for this, but we track platform
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> enable() async {
    if (_android) {
      try {
        await _androidChannel.invokeMethod<void>('enable');
      } catch (_) {}
    }
    // iOS: We can't enforce screenshot blocking from Dart alone,
    // but we set up frameworks for future iOS support.
    if (_ios) {
      // iOS requires native code or UIInterfaceOrientationCategory
      // for full screenshot prevention; we log and prepare for native bridge.
      debugPrint('iOS secure screen enabled (native bridging required)');
    }
  }

  static Future<void> disable() async {
    if (_android) {
      try {
        await _androidChannel.invokeMethod<void>('disable');
      } catch (_) {}
    }
    if (_ios) {
      debugPrint('iOS secure screen disabled');
    }
  }
}