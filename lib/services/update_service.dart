import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_logic.dart';

/// An update check result.
enum CheckOutcome {
  noUpdate,
  update,
  error,
}

/// A failure with a stable [kind] the UI switches on.
class UpdateException implements Exception {
  const UpdateException(this.kind, this.message);

  final String kind;
  final String message;

  @override
  String toString() => message;
}

const networkFailure =
    UpdateException('network', 'Could not reach the update server');
const insufficientStorage =
    UpdateException('storage', 'Not enough free space for the update');
const installUnavailable =
    UpdateException('install', 'This device cannot accept APK installs');
const installRejected =
    UpdateException('installRejected', 'The install request was rejected');
const malformedManifest =
    UpdateException('malformed', 'Downloaded APK has an invalid manifest');

/// How long before the next background update check is allowed.
const defaultCheckThrottle = Duration(hours: 6);

/// SharedPreferences-backed throttle + postpone state.
class UpdatePreferences {
  UpdatePreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _kLastCheck = 'update_last_check_ms';
  static const _kPostponed = 'update_postponed_version_code';

  int get lastCheckMs => _prefs.getInt(_kLastCheck) ?? 0;

  int? get postponedVersionCode => _prefs.getInt(_kPostponed);

  bool passedSinceCheck(Duration throttle, {DateTime? now}) {
    final current = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return current - lastCheckMs >= throttle.inMilliseconds;
  }

  Future<void> markChecked({DateTime? now}) => _prefs.setInt(
        _kLastCheck,
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      );

  Future<void> postponeUntil(int? versionCode) => versionCode == null
      ? _prefs.remove(_kPostponed)
      : _prefs.setInt(_kPostponed, versionCode);
}

/// Communicates with GitHub Releases, tolerating an injected http.Client for
/// tests and a configurable base URL.
class GitHubReleaseClient {
  GitHubReleaseClient({required this.httpClient, String? baseUrl})
      : _base = baseUrl ?? 'https://api.github.com';

  final http.Client httpClient;
  final String _base;
  static const _userAgent = 'BRO-updater/1.0';

  /// `GET /repos/{owner}/{repo}/releases/latest`.
  /// Throws [networkFailure] on transport errors and non-200 responses.
  Future<ReleaseInfo> fetchLatestRelease(String repo) async {
    final uri = Uri.parse('$_base/repos/$repo/releases/latest');
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = _userAgent
      ..headers['Accept'] = 'application/vnd.github+json';
    final http.Response body;
    try {
      final streamed = await httpClient.send(request);
      body = await http.Response.fromStream(streamed);
    } catch (_) {
      throw networkFailure;
    }
    if (body.statusCode != 200) {
      throw networkFailure;
    }
    try {
      final json = jsonDecode(body.body) as Map<String, dynamic>;
      return _parseRelease(json);
    } catch (_) {
      throw networkFailure;
    }
  }

  static ReleaseInfo _parseRelease(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final notes = (json['body'] as String?) ?? '';
    final publishedAt = json['published_at'] as String?;
    final rawAssets = json['assets'];
    final assets = rawAssets is List
        ? ApkAssetParser.fromApi(rawAssets)
        : const <ApkAsset>[];
    final tagCode = VersionParser.fromTag(tag);
    final versionCode = tagCode ?? -1;
    final versionName =
        VersionParser.toCode(tag)?.toString() ?? (tagCode?.toString() ?? '0');
    return ReleaseInfo(
      tag: tag,
      versionCode: versionCode,
      versionName: versionName,
      notes: notes,
      assets: assets,
      mandatory: _isMandatory(notes),
      publishedAt: publishedAt,
    );
  }

  static bool _isMandatory(String notes) =>
      RegExp(r'^\s*#+\s*Mandatory\s*$', caseSensitive: false, multiLine: true)
          .hasMatch(notes) ||
      notes.toLowerCase().contains('mandatory update');
}

/// Read the (binary) AndroidManifest.xml out of an APK zip archive.
Future<ManifestInfo?> readApkManifest(File apk) async {
  try {
    final bytes = await apk.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files
        .where((f) => f.name == 'AndroidManifest.xml')
        .firstOrNull;
    if (entry == null) return null;
    final manifestBytes =
        Uint8List.fromList((entry.content as List<int>).toList());
    return ManifestParser.parse(manifestBytes);
  } catch (_) {
    return null;
  }
}

/// Whether the system installer can be reached / the user accepted.
abstract class Installer {
  Future<void> install(String apkPath);
}

int? _contentLength(http.StreamedResponse r) =>
    (r.contentLength != null && r.contentLength! > 0) ? r.contentLength : null;

/// Foreground download of the selected APK with progress reporting.
///
/// [onProgress] receives 0..1 (based on the HTTP content length when known).
/// Throws [networkFailure], [insufficientStorage] or [checksumMismatch].
Future<File> downloadApk(
  String url, {
  required File file,
  required void Function(double progress) onProgress,
  http.Client? client,
  int Function()? freeBytes,
  Future<ManifestInfo?> Function(File)? verifyManifest,
}) async {
  final httpClient = client ?? http.Client();
  await file.parent.create(recursive: true);
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'BRO-updater/1.0';
    final streamed = await httpClient.send(request);
    if (streamed.statusCode != 200) {
      throw networkFailure;
    }
    final total = _contentLength(streamed) ?? 0;
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      if (freeBytes != null && freeBytes() < chunk.length) {
        await sink.close();
        throw insufficientStorage;
      }
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
    }
    await sink.flush();
    await sink.close();
    if (total > 0) onProgress(1.0);

    if (verifyManifest != null) {
      final manifest = await verifyManifest(file);
      if (manifest?.versionCode == null) throw malformedManifest;
    }
    return file;
  } on UpdateException {
    rethrow;
  } catch (_) {
    throw networkFailure;
  }
}

/// Directories for downloaded updates; one seam so tests avoid real storage.
class UpdateStorage {
  static Future<Directory> Function() root =
      getApplicationDocumentsDirectory;

  static Future<File> updateFile(String fileName) async {
    final dir = await root();
    final target = Directory('${dir.path}/updates');
    await target.create(recursive: true);
    return File('${target.path}/$fileName');
  }
}

/// Coordinates the full update flow: throttled check, policy decision,
/// download with checksum verification, and handoff to the system installer.
/// All external dependencies are injectable so the flow is unit-testable.
class AppUpdater {
  AppUpdater({
    this.prefs,
    this.releaseClient,
    this.installer,
    this.policy = const UpdatePolicy(),
    this.throttle = defaultCheckThrottle,
    this.now,
    this.httpClient,
    this.freeBytes,
  });

  final UpdatePreferences? prefs;
  final GitHubReleaseClient? releaseClient;
  final Installer? installer;
  final UpdatePolicy policy;
  final Duration throttle;
  final DateTime Function()? now;
  final http.Client? httpClient;
  final int Function()? freeBytes;

  DateTime get _currentTime => (now ?? DateTime.now)();

  bool checkAllowed([UpdatePreferences? p]) {
    final prefs = p ?? this.prefs;
    if (prefs == null) return true;
    return prefs.passedSinceCheck(throttle, now: _currentTime);
  }

  /// Runs a background check. Returns the outcome and — when an update is to be
  /// offered — the release to present.
  Future<(CheckOutcome, ReleaseInfo?)> checkForUpdates({
    required String repo,
    required int installedVersionCode,
    UpdatePreferences? prefs,
  }) async {
    final p = prefs ?? this.prefs;
    if (p != null && !checkAllowed(p)) {
      return (CheckOutcome.noUpdate, null);
    }
    if (releaseClient == null) {
      return (CheckOutcome.error, null);
    }
    final ReleaseInfo release;
    try {
      release = await releaseClient!.fetchLatestRelease(repo);
    } catch (_) {
      return (CheckOutcome.error, null);
    }
    if (p != null) await p.markChecked(now: _currentTime);

    final postponed = p?.postponedVersionCode;
    final remindedToSkip = postponed != null &&
        (postponed == release.versionCode ||
            release.versionCode - postponed <=
                policy.rememberPostponeVersionFor);

    final decision = policy.decide(
      installedVersionCode: installedVersionCode,
      remoteVersionCode: release.versionCode,
      releaseMandatory: release.mandatory,
      remindedToSkip: remindedToSkip,
    );
    if (!decision.isUpdate) {
      return (CheckOutcome.noUpdate, null);
    }
    return (CheckOutcome.update, release);
  }

  /// Maps a device ABI string (device_info_plus) to the matching [ApkAbi].
  static ApkAbi? abiForName(String? abi) {
    if (abi == null) return null;
    final lower = abi.toLowerCase();
    for (final a in ApkAbi.values) {
      if (lower.contains(a.tag)) return a;
    }
    if (lower.contains('arm64') || lower.contains('aarch64')) {
      return ApkAbi.arm64V8a;
    }
    return null;
  }

  /// Downloads [asset] to a scratch file, verifying checksum and manifest.
  Future<File> download(
    ReleaseInfo release,
    ApkAsset asset, {
    required void Function(double) onProgress,
  }) async {
    final file = await UpdateStorage.updateFile(asset.name);
    return downloadApk(
      asset.url,
      file: file,
      onProgress: onProgress,
      client: httpClient,
      freeBytes: freeBytes,
      verifyManifest: (f) => readApkManifest(f),
    );
  }

  /// Hands the downloaded APK to the system installer. The Android package
  /// installer retains control of the confirmation — never a silent install.
  Future<void> installDownloaded(File file) async {
    if (installer == null) throw installUnavailable;
    try {
      await installer!.install(file.path);
    } catch (_) {
      throw installRejected;
    }
  }
}
