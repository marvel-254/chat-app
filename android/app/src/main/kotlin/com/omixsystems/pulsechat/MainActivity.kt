package com.omixsystems.pulsechat

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

class MainActivity : FlutterFragmentActivity() {
    private var crypto: CryptoRuntime? = null
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopService(Intent(this, CallCaptureService::class.java))
        crypto?.close(); crypto = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bro/openpgp").setMethodCallHandler { call, result ->
            if (call.method != "run" || call.arguments !is String) result.notImplemented() else {
                val runtime = crypto ?: CryptoRuntime(this).also { crypto = it }
                runtime.run(call.arguments as String, result)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bro/capture").setMethodCallHandler { call, result ->
            try {
                val intent = Intent(this, CallCaptureService::class.java)
                when (call.method) {
                    "start" -> { intent.putExtra("video", call.arguments == true); if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent) }
                    "stop" -> stopService(intent)
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (_: Exception) { result.error("CAPTURE", "Call service could not start", null) }
        }

        // Existing secure screen channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bro/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // App update channel for installing downloaded APKs
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.omixsystems.pulsechat/app_update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_ARGS", "Missing APK path", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installApk(filePath: String) {
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            throw FileNotFoundException("APK not found: $filePath")
        }

        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val authority = "${applicationContext.packageName}.fileprovider"
            // For files in the app's documents directory, use FileProvider
            FileProvider.getUriForFile(applicationContext, authority, apkFile)
        } else {
            Uri.fromFile(apkFile)
        }

        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
            data = uri
            type = "application/vnd.android.package-archive"
        }

        startActivity(installIntent)
    }
}
