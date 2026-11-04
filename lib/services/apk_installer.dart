import 'package:flutter/services.dart';

import 'update_service.dart';

/// Hands the downloaded APK to the Android system package installer through a
/// native method channel. Android's own installer screen (and the OS-level
/// confirmation) remains in control — this never performs a silent install.
class ApkInstaller implements Installer {
  @override
  Future<void> install(String apkPath) async {
    try {
      await _channel.invokeMethod<void>(
        'installApk',
        {'path': apkPath},
      );
    } on PlatformException {
      throw installRejected;
    }
  }

  static const _channel = MethodChannel('brotools/updater');
}
