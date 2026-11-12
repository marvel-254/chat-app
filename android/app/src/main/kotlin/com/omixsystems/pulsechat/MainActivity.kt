package com.omixsystems.pulsechat

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity.
 *
 * Exposes a small "bro/secure" method channel so Dart can flip
 * FLAG_SECURE for locked conversations. This replaces the abandoned
 * `flutter_windowmanager` plugin, whose Android build script still calls
 * `jcenter()` and therefore cannot be evaluated by Gradle 9 (that plugin
 * broke every release build from v63 onwards).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "bro/secure"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the recorder/media session flags off the lock screen by default.
        // Screenshot protection is opt-in per conversation via the channel above.
    }
}
