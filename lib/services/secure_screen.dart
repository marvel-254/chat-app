import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Blocks screenshots/recordings on Android while a locked chat is open.
class SecureScreen {
  static const _channel = MethodChannel('bro/secure_screen');

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> enable() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('enable');
    } catch (_) {}
  }

  static Future<void> disable() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('disable');
    } catch (_) {}
  }
}
