import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks GitHub Releases for a newer signed APK than this build.
/// Downloads are verified against the release asset digest and an APK/ZIP
/// header before the Android installer is invoked.
class AppUpdate {
  static const _repo = 'marvel-254/chat-app';
  static const _seenKey = 'app_update_seen_tag';
  static const _snoozedTagKey = 'app_update_snoozed_tag';
  static const _snoozedUntilKey = 'app_update_snoozed_until';
  static const _lastCheckKey = 'app_update_last_check_ts';
  static const checkInterval = Duration(hours: 6);

  static const _channel = MethodChannel('com.omixsystems.pulsechat/app_update');
  static const _apkSignature = <int>[0x50, 0x4b, 0x03, 0x04];

  /// Parse `v1.4.5` or `1.4.5+21` into comparable numbers.
  static List<int>? parseVersion(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (cleaned.isEmpty) return null;
    final core = cleaned.split('+').first;
    final parts = core.split(RegExp(r'[.-]'));
    if (parts.isEmpty || parts.length > 6) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final match = RegExp(r'^\d+').firstMatch(part.trim());
      if (match == null) return null;
      numbers.add(int.tryParse(match.group(0)!) ?? -1);
    }
    if (numbers.any((value) => value < 0)) return null;
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }

  /// True when [candidate] is a higher semantic version than [current].
  static bool isNewer(String candidate, String current) {
    final a = parseVersion(candidate);
    final b = parseVersion(current);
    if (a == null || b == null) return false;
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left > right) return true;
      if (left < right) return false;
    }
    return false;
  }

  static String _sha256Hex(List<int> bytes) {
    final digest = SHA256Digest();
    final output = Uint8List(digest.digestSize);
    final input = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    digest.update(input, 0, input.length);
    digest.doFinal(output, 0);
    return output.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Returns null when [bytes] match the announced digest, otherwise an error.
  static String? verifyDigest(List<int> bytes, String? expectedDigest) {
    if (bytes.length < 4) return 'The downloaded file is empty.';
    for (var i = 0; i < _apkSignature.length; i++) {
      if (bytes[i] != _apkSignature[i]) {
        return 'The downloaded file is not an Android package.';
      }
    }
    final expected = expectedDigest?.trim().toLowerCase();
    if (expected == null ||
        !expected.startsWith('sha256:') ||
        expected.length != 71) {
      return null; // No usable digest published for this asset.
    }
    final announced = expected.substring(7);
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(announced) &&
        _sha256Hex(bytes) == announced) {
      return null;
    }
    return 'The update did not match the checksum published on GitHub.';
  }

  /// Check if a newer release exists and return its info.
  static Future<AppUpdateInfo?> latestNewerThan(String currentVersion) async {
    if (parseVersion(currentVersion) == null) return null;
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
      if (!isNewer(tag, currentVersion)) return null;
      final assets = json['assets'];
      String? apk;
      String? digest;
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = asset['name'] as String? ?? '';
          final url = asset['browser_download_url'] as String?;
          if (url == null || !name.endsWith('.apk')) continue;
          if (name.contains('arm64-v8a')) {
            apk = url;
            digest = asset['digest'] as String?;
            break;
          }
          apk ??= url;
          digest ??= asset['digest'] as String?;
        }
      }
      return AppUpdateInfo(
        tag: tag.startsWith('v') ? tag : 'v$tag',
        name: json['name'] as String? ?? tag,
        notes: json['body'] as String? ?? '',
        htmlUrl: json['html_url'] as String? ??
            'https://github.com/$_repo/releases/latest',
        apkUrl: apk,
        expectedSha256: digest,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> _shouldCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastCheckKey) ?? 0;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= checkInterval;
  }

  /// Download, verify and hand an APK to the Android installer.
  /// Returns the path to the verified file, or null on failure.
  static Future<String?> downloadAndInstall({
    required String apkUrl,
    required ProgressCallback onProgress,
    String? expectedSha256,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/bro_update.apk';
      final file = File(filePath);
      if (await file.exists()) await file.delete();

      final response = await http.get(
        Uri.parse(apkUrl),
        headers: const {'User-Agent': 'BRO-chat-app'},
      ).timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;
      final verificationError = verifyDigest(bytes, expectedSha256);
      if (verificationError != null) {
        debugPrint('AppUpdate verification failed: $verificationError');
        return null;
      }
      await file.writeAsBytes(bytes);
      onProgress(1.0, bytes.length, response.contentLength ?? bytes.length);

      if (Platform.isAndroid) {
        try {
          final success = await _channel
              .invokeMethod<bool?>('installApk', {'path': filePath}) ?? false;
          if (success) return filePath;
        } on PlatformException catch (_) {
          // Fall back to opening the verified file with an intent.
        }
      }

      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return filePath;
      }
      return null;
    } catch (e) {
      debugPrint('AppUpdate download error: $e');
      return null;
    }
  }

  /// Show the update dialog with download progress.
  static Future<void> promptIfNeeded({
    required BuildContext context,
    required String currentVersion,
    AppUpdateInfo? latest,
    bool forcePrompt = false,
  }) async {
    final info = latest ?? await latestNewerThan(currentVersion);
    if (info == null || !context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!forcePrompt && prefs.getString(_seenKey) == info.tag) return;
    final snoozedUntil = prefs.getInt(_snoozedUntilKey) ?? 0;
    if (!forcePrompt &&
        prefs.getString(_snoozedTagKey) == info.tag &&
        DateTime.now().millisecondsSinceEpoch < snoozedUntil) {
      return;
    }
    if (!context.mounted) return;

    final notesPreview = info.notes.length > 200
        ? '${info.notes.substring(0, 200)}...'
        : info.notes;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.system_update, size: 48),
        title: Text('${info.name} is ready'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                kIsWeb
                    ? 'A newer version of the BRO web app is available. Refresh to load the latest features and fixes.'
                    : 'A new version of BRO is available. Update now for the latest features and fixes.',
              ),
              if (notesPreview.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('What\'s new:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(notesPreview,
                    style: const TextStyle(fontSize: 13)),
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
            child: Text(kIsWeb ? 'Refresh web app' : 'Update now'),
          ),
        ],
      ),
    );

    await _markChecked();
    if (confirmed != true) {
      // Remind again tomorrow if this release is still current.
      await prefs.setString(_snoozedTagKey, info.tag);
      await prefs.setInt(
        _snoozedUntilKey,
        DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
      return;
    }
    if (!context.mounted) return;

    if (kIsWeb) {
      final reloaded = await launchUrl(
        Uri.base,
        webOnlyWindowName: '_self',
      );
      if (reloaded) await prefs.setString(_seenKey, info.tag);
      return;
    }

    if (info.apkUrl == null) {
      // Never try to "install" the HTML release page.
      final uri = Uri.tryParse(info.htmlUrl);
      if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      await prefs.setString(_seenKey, info.tag);
      return;
    }

    final installed = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateProgressDialog(info: info),
    );
    // Only suppress future prompts after a successful hand-off to the
    // installer; a failed download should be retried on the next launch.
    if (installed != null) await prefs.setString(_seenKey, info.tag);
  }

  /// Check for a release from Settings and show a notice or update prompt.
  static Future<void> checkNow({
    required BuildContext context,
    required String currentVersion,
  }) async {
    if (parseVersion(currentVersion) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Update checks are available in release builds.'),
        ),
      );
      return;
    }
    final info = await latestNewerThan(currentVersion);
    if (!context.mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BRO is up to date.')),
      );
      return;
    }
    await promptIfNeeded(
      context: context,
      currentVersion: currentVersion,
      latest: info,
      forcePrompt: true,
    );
  }

  /// Check periodically; the caller decides when to present any update.
  static Future<AppUpdateInfo?> backgroundCheck(String currentVersion) async {
    if (!await _shouldCheck()) return null;
    final info = await latestNewerThan(currentVersion);
    if (info != null) await _markChecked();
    return info;
  }
}

class UpdateProgressDialog extends StatefulWidget {
  const UpdateProgressDialog({super.key, required this.info});

  final AppUpdateInfo info;

  @override
  State<UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<UpdateProgressDialog> {
  double _progress = 0;
  bool _done = false;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final path = await AppUpdate.downloadAndInstall(
      apkUrl: widget.info.apkUrl!,
      expectedSha256: widget.info.expectedSha256,
      onProgress: (progress, _, __) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );
    if (!mounted) return;
    setState(() {
      if (path == null) {
        _error = 'The update could not be downloaded or verified. '
            'Please try again later.';
      } else {
        _done = true;
      }
    });
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Updating BRO'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _done ? null : _progress.clamp(0.0, 1.0),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? (_done ? 'Installing...' : 'Downloading update...'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text('Do not close the app during update.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
    );
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    this.apkUrl,
    this.expectedSha256,
  });

  final String tag;
  final String name;
  final String notes;
  final String htmlUrl;
  final String? apkUrl;
  final String? expectedSha256;
}

/// Callback signature for download progress.
/// [progress] is 0.0–1.0, or -1 if total size is unknown.
/// [downloaded] and [total] are byte counts.
typedef ProgressCallback = void Function(double progress, int downloaded, int total);
