import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks GitHub Releases for a newer signed APK than this build.
class AppUpdate {
  static const _repo = 'marvel-254/chat-app';
  static const _seenKey = 'app_update_seen_tag';

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
      ).timeout(const Duration(seconds: 8));
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

  static Future<void> promptIfNeeded({
    required BuildContext context,
    required String buildNumber,
  }) async {
    final info = await latestNewerThan(buildNumber);
    if (info == null || !context.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_seenKey) == info.tag) return;
    if (!context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${info.name} is ready'),
        content: Text(
          'You are on build $buildNumber. A newer signed APK is on GitHub.\n\n'
          'Download and install it to keep BRO up to date.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    await prefs.setString(_seenKey, info.tag);
    if (go == true) {
      final target = Uri.parse(info.apkUrl ?? info.htmlUrl);
      await launchUrl(target, mode: LaunchMode.externalApplication);
    }
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
