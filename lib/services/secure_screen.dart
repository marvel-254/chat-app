import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Screenshot / screen-recording protection for sensitive chats.
///
/// Backed by `FLAG_SECURE` on Android through the `bro/secure` method channel
/// implemented in `MainActivity.kt`. This replaced the abandoned
/// `flutter_windowmanager` package, which broke release builds because its
/// Gradle script still referenced the removed `jcenter()` repository.
///
/// On iOS and the web there is no equivalent OS-level flag, so the calls are
/// no-ops and [isSupported] reports false. (iOS can only react after the fact
/// via `applicationWillResignActive` or detect captures through the
/// UIScreen-isCaptured notification, neither of which can *prevent* a capture.)
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('bro/secure');

  /// Whether the current platform can actually block screenshots.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Adds or removes `FLAG_SECURE` for the current window.
  ///
  /// Never throws: screenshot protection is best-effort, and a failure here
  /// must not break opening or leaving a conversation.
  static Future<void> setSecure(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
    } catch (_) {}
  }
}
