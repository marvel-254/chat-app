import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks GitHub Releases for a newer signed APK than this build.
/// Supports direct APK download with progress tracking and Android
/// PackageInstaller for seamless in-app installation.
class AppUpdate {
  static const _repo = 'marvel-254/chat-app';
  static const _seenKey = 'app_update_seen_tag';
  static const _lastCheckKey = 'app_update_last_check_ts';
  static const checkInterval = Duration(hours: 6);

  // Platform channel for Android PackageInstaller
  static const _channel = MethodChannel('com.omixsystems.pulsechat/app_update');

  /// Check if a newer release exists and return its info.
  static Future<AppUpdateInfo?> latestNewerThan(String buildNumber) async {
    final current = int.tryParse(buildNumber);
    if (current == null || current <= 0) return null;
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'BRO-chat-app',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final latest = int.tryParse(tag.replaceFirst(RegExp(r'^v'), ''));
      if (latest == null || latest <= current) return null;
      final assets = json['assets'];
      String? apk;
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = asset['name'] as String? ?? '';
          final url = asset['browser_download_url'] as String?;
          if (url == null) continue;
          if (name.contains('arm64-v8a') && name.endsWith('.apk')) {
            apk = url;
            break;
          }
          if (apk == null && name.endsWith('.apk')) apk = url;
        }
      }
      return AppUpdateInfo(
        tag: tag.startsWith('v') ? tag : 'v$tag',
        name: json['name'] as String? ?? tag,
        notes: json['body'] as String? ?? '',
        htmlUrl: json['html_url'] as String? ??
            'https://github.com/$_repo/releases/latest',
        apkUrl: apk,
      );
    } catch (_) {
      return null;
    }
  }

  /// Record the timestamp of the last update check.
  static Future<void> _markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Check if enough time has passed since the last check.
  static Future<bool> _shouldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastCheckKey) ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= checkInterval;
  }

  /// Download an APK directly to the device and trigger installation.
  /// Returns the path to the downloaded file, or null on failure.
  static Future<String?> downloadAndInstall({
    required String apkUrl,
    required ProgressCallback onProgress,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'bro_update.apk';
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      // Delete any previous partial download
      if (await file.exists()) await file.delete();

      final response = await http.get(
        Uri.parse(apkUrl),
        headers: {'User-Agent': 'BRO-chat-app'},
      ).timeout(const Duration(seconds: 120));

      final totalBytes = response.contentLength ?? 0;
      final bytes = response.bodyBytes;
      await file.writeAsBytes(bytes);
      onProgress(1.0, bytes.length, totalBytes);

      // On Android, try to use PackageInstaller for seamless install
      if (Platform.isAndroid) {
        try {
          final success = await _channel
              .invokeMethod<bool?>('installApk', {'path': filePath}) ?? false;
          if (success) return filePath;
        } on PlatformException catch (_) {
          // Fallback: open with intent
        }
      }

      // Fallback: launch the file URI
      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
      return filePath;
    } catch (e) {
      debugPrint('AppUpdate download error: $e');
      return null;
    }
  }

  /// Show the update dialog with download progress.
  static Future<void> promptIfNeeded({
    required BuildContext context,
    required String buildNumber,
  }) async {
    final info = await latestNewerThan(buildNumber);
    if (info == null || !context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_seenKey) == info.tag) return;
    if (!context.mounted) return;

    // Truncate release notes for the dialog
    final notesPreview = info.notes.isNotEmpty
        ? (info.notes.length > 200
            ? '${info.notes.substring(0, 200)}...'
            : info.notes)
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update, size: 48),
        title: Text('$info.name is ready'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version of BRO is available. Update now for the latest features and fixes.',
              ),
              if (notesPreview.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('What\'s new:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  notesPreview,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Remind me later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update now'),
          ),
        ],
      ),
    );

    // Mark as seen so we don't nag on every launch for the same tag
    await prefs.setString(_seenKey, info.tag);
    await _markChecked();

    if (confirmed != true) return;
    if (!context.mounted) return;

    // Show download progress dialog
    await _showDownloadDialog(
      context: context,
      info: info,
      buildNumber: buildNumber,
    );
  }

  /// Show a dialog that tracks download and install progress.
  static Future<void> _showDownloadDialog({
    required BuildContext context,
    required AppUpdateInfo info,
    required String buildNumber,
  }) async {
    double progress = 0;
    bool done = false;
    Timer? refreshTimer;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          refreshTimer?.cancel();
          refreshTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
            setDialogState(() {});
          });

          String statusText;
          if (done) {
            statusText = 'Installing...';
          } else if (progress < 0) {
            statusText = 'Downloading...';
          } else {
            statusText = 'Downloading... ${(progress * 100).toStringAsFixed(0)}%';
          }

          return AlertDialog(
            title: const Text('Updating BRO'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: done ? null : progress.clamp(0.0, 1.0),
                ),
                const SizedBox(height: 12),
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Do not close the app during update.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              if (done)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
            ],
          );
        },
      ),
    );

    refreshTimer?.cancel();

    // Start the download
    await downloadAndInstall(
      apkUrl: info.apkUrl ?? info.htmlUrl,
      onProgress: (p, _, __) {
        if (p >= 1.0) {
          done = true;
        } else {
          progress = p;
        }
      },
    );
  }

  /// Background check: silently check for updates periodically.
  /// If an update is found, store it so the next UI prompt can show it.
  static Future<AppUpdateInfo?> backgroundCheck(String buildNumber) async {
    if (!await _shouldCheck()) return null;
    final info = await latestNewerThan(buildNumber);
    if (info != null) await _markChecked();
    return info;
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    this.apkUrl,
  });

  final String tag;
  final String name;
  final String notes;
  final String htmlUrl;
  final String? apkUrl;
}

/// Callback signature for download progress.
/// [progress] is 0.0–1.0, or -1 if total size is unknown.
/// [downloaded] and [total] are byte counts.
typedef ProgressCallback = void Function(double progress, int downloaded, int total);
