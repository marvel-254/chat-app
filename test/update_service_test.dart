import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nyx_chat/services/update_logic.dart';
import 'package:nyx_chat/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An http client whose response stream dies mid-download.
class _FailMidStreamClient extends http.BaseClient {
  _FailMidStreamClient(this._contentLength);

  final int _contentLength;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> stream() async* {
      yield List<int>.filled(16, 1);
      throw http.ClientException('connection reset');
    }

    return http.StreamedResponse(stream(), 200, contentLength: _contentLength);
  }
}

Future<File> buildFixtureApk() async {
  final manifest =
      await File('test/fixtures/real_manifest.bin').readAsBytes();
  final archive = Archive()
    ..addFile(
      ArchiveFile('AndroidManifest.xml', manifest.length, manifest),
    );
  final bytes = ZipEncoder().encode(archive);
  final file = File(
    '${Directory.systemTemp.createTempSync('fixture_apk').path}/app.apk',
  )..writeAsBytesSync(bytes);
  return file;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('sha256Hex', () {
    test('produces the known SHA-256 of "abc"', () {
      expect(sha256Hex(utf8.encode('abc')),
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('UpdatePreferences', () {
    test('defaults to no check time and no postponed version', () async {
      final prefs = UpdatePreferences(await SharedPreferences.getInstance());
      expect(prefs.lastCheckMs, 0);
      expect(prefs.postponedVersionCode, isNull);
    });

    test('passedSinceCheck respects the throttle window', () async {
      final prefs = UpdatePreferences(await SharedPreferences.getInstance());
      final t0 = DateTime(2026, 1, 1);
      expect(prefs.passedSinceCheck(const Duration(hours: 6),
          now: t0), isTrue);
      await prefs.markChecked(now: t0);
      expect(
          prefs.passedSinceCheck(const Duration(hours: 6),
              now: t0.add(const Duration(hours: 5))),
          isFalse);
      expect(
          prefs.passedSinceCheck(const Duration(hours: 6),
              now: t0.add(const Duration(minutes: 360))),
          isTrue);
    });

    test('postponeUntil stores and clears the version', () async {
      final prefs = UpdatePreferences(await SharedPreferences.getInstance());
      await prefs.postponeUntil(151);
      expect(prefs.postponedVersionCode, 151);
      await prefs.postponeUntil(null);
      expect(prefs.postponedVersionCode, isNull);
    });
  });

  group('GitHubReleaseClient', () {
    Map<String, dynamic> releaseJson({String notes = ''}) => {
          'tag_name': 'v149',
          'name': 'v149',
          'body': notes,
          'published_at': '2026-01-01T00:00:00Z',
          'assets': [
            {
              'name': 'app-arm64-v8a-release.apk',
              'browser_download_url': 'https://example.com/app-arm64-v8a-release.apk',
              'size': 1234567,
            },
            {
              'name': 'app-armeabi-v7a-release.apk',
              'browser_download_url': 'https://example.com/app-armeabi-v7a-release.apk',
              'size': 1000000,
            },
          ],
        };

    test('parses a latest release with assets', () async {
      final client = GitHubReleaseClient(
        httpClient: MockClient((req) async =>
            http.Response(jsonEncode(releaseJson()), 200, headers: {
              'content-type': 'application/json',
            })),
      );
      final release =
          await client.fetchLatestRelease('marvel-254/chat-app');
      expect(release.tag, 'v149');
      expect(release.versionCode, 149);
      expect(release.assets, hasLength(2));
      expect(release.mandatory, isFalse);
      expect(release.publishedAt, '2026-01-01T00:00:00Z');
    });

    test('flags a release as mandatory when body mentions it', () async {
      final client = GitHubReleaseClient(
        httpClient: MockClient((req) async => http.Response(
            jsonEncode(releaseJson(notes: '## Mandatory\nPopulated content')),
            200)),
      );
      final release =
          await client.fetchLatestRelease('marvel-254/chat-app');
      expect(release.mandatory, isTrue);
    });

    test('flags a release as mandatory for "mandatory update" phrasing', () async {
      final client = GitHubReleaseClient(
        httpClient: MockClient((req) async => http.Response(
            jsonEncode(releaseJson(notes: 'This is a mandatory update.')),
            200)),
      );
      final release =
          await client.fetchLatestRelease('marvel-254/chat-app');
      expect(release.mandatory, isTrue);
    });

    test('throws networkFailure on a non-200 response', () async {
      final client = GitHubReleaseClient(
        httpClient: MockClient((req) async => http.Response('not found', 404)),
      );
      expect(() => client.fetchLatestRelease('marvel-254/chat-app'),
          throwsA(isA<UpdateException>()));
    });

    test('throws networkFailure on a transport error', () async {
      final client = GitHubReleaseClient(
        httpClient: MockClient(
            (req) async => throw http.ClientException('offline')),
      );
      expect(() => client.fetchLatestRelease('marvel-254/chat-app'),
          throwsA(isA<UpdateException>()));
    });
  });

  group('AppUpdater.abfForName', () {
    test('maps device ABI strings to an enum', () {
      expect(AppUpdater.abiForName('arm64-v8a'), isNotNull);
      expect(AppUpdater.abiForName('arm64-v8a')!.tag, 'arm64-v8a');
      expect(AppUpdater.abiForName('x86_64'), isNotNull);
      expect(AppUpdater.abiForName('armeabi-v7a'), isNotNull);
      expect(AppUpdater.abiForName('unknown-abi'), isNull);
      expect(AppUpdater.abiForName(null), isNull);
    });
  });

  group('AppUpdater.checkForUpdates', () {
    http.Client okClientFor(int versionCode) => MockClient((req) async =>
        http.Response(
            jsonEncode({
              'tag_name': 'v$versionCode',
              'name': 'v$versionCode',
              'body': '',
              'published_at': null,
              'assets': [
                {
                  'name': 'app-arm64-v8a-release.apk',
                  'browser_download_url': 'https://example.com/a.apk',
                  'size': 1,
                },
              ],
            }),
            200));

    test('reports noUpdate when the throttle has not elapsed', () async {
      final prefs = UpdatePreferences(await SharedPreferences.getInstance());
      final now = DateTime(2026, 1, 1);
      await prefs.markChecked(now: now);
      final updater = AppUpdater(
        prefs: prefs,
        releaseClient: GitHubReleaseClient(httpClient: okClientFor(200)),
        now: () => now.add(const Duration(hours: 1)),
        throttle: const Duration(hours: 6),
      );
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 100);
      expect(outcome, CheckOutcome.noUpdate);
      expect(release, isNull);
    });

    test('returns error when no release client is configured', () async {
      final updater = AppUpdater(prefs: await _freshPrefs());
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 100);
      expect(outcome, CheckOutcome.error);
      expect(release, isNull);
    });

    test('returns error when the network request fails', () async {
      final updater = AppUpdater(
        prefs: await _freshPrefs(),
        releaseClient: GitHubReleaseClient(
          httpClient: MockClient((req) async => http.Response('x', 500)),
        ),
      );
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 100);
      expect(outcome, CheckOutcome.error);
    });

    test('returns update for a newer release', () async {
      final updater = AppUpdater(
        prefs: await _freshPrefs(),
        releaseClient:
            GitHubReleaseClient(httpClient: okClientFor(200)),
      );
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 100);
      expect(outcome, CheckOutcome.update);
      expect(release, isNotNull);
      expect(release!.versionCode, 200);
    });

    test('returns noUpdate for an older or equal release', () async {
      final updater = AppUpdater(
        prefs: await _freshPrefs(),
        releaseClient: GitHubReleaseClient(httpClient: okClientFor(99)),
      );
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 100);
      expect(outcome, CheckOutcome.noUpdate);
    });

    test('postponed release is suppressed within the window', () async {
      SharedPreferences.setMockInitialValues({'update_postponed_version_code': 151});
      final updater = AppUpdater(
        prefs: await _freshPrefs(),
        releaseClient: GitHubReleaseClient(httpClient: okClientFor(151)),
        policy: const UpdatePolicy(optionalWindow: 5),
      );
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 149);
      expect(outcome, CheckOutcome.noUpdate);
    });

    test('a wide version jump is mandatory even without the marker', () async {
      final updater = AppUpdater(
        prefs: await _freshPrefs(),
        releaseClient: GitHubReleaseClient(httpClient: okClientFor(200)),
      );
      final (outcome, release) =
          await updater.checkForUpdates(repo: 'r', installedVersionCode: 100);
      expect(outcome, CheckOutcome.update);
      expect(release!.mandatory, isFalse);
      // policy decides the jump is beyond the optional window
      final decision = const UpdatePolicy().decide(
        installedVersionCode: 100,
        remoteVersionCode: 200,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(decision.priority.name, 'mandatory');
    });
  });

  group('downloadApk', () {
    late Directory tmp;
    late File file;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('dl_test');
      file = File('${tmp.path}/out.apk');
    });

    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('downloads a file and reports progress to 1.0', () async {
      final body = List<int>.generate(1024, (i) => i & 0xFF);
      final client = MockClient((req) async =>
          http.Response.bytes(body, 200));
      var last = 0.0;
      final result = await downloadApk(
        'https://example.com/a.apk',
        file: file,
        onProgress: (p) => last = p,
        client: client,
      );
      expect(await result.length(), 1024);
      expect(last, 1.0);
    });

    test('throws networkFailure on a non-200 response', () async {
      final client =
          MockClient((req) async => http.Response('nope', 404));
      expect(
          () => downloadApk('https://e/a.apk',
              file: file, onProgress: (_) {}, client: client),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'network')));
    });

    test('throws checksumMismatch when the hash does not match', () async {
      final client =
          MockClient((req) async => http.Response('hello', 200));
      file.writeAsBytesSync([1, 2, 3, 4, 5]);
      expect(
          () => downloadApk('https://e/a.apk',
              file: file,
              onProgress: (_) {},
              client: client,
              expectedSha256: 'deadbeef'),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'checksum')));
    });

    test('accepts a matching checksum', () async {
      final body = 'same-bytes';
      final client =
          MockClient((req) async => http.Response(body, 200));
      final result = await downloadApk(
        'https://e/a.apk',
        file: file,
        onProgress: (_) {},
        client: client,
        expectedSha256: sha256Hex(utf8.encode(body)),
      );
      expect(result, same(file));
    });

    test('throws insufficientStorage when free space runs out', () async {
      final client =
          MockClient((req) async => http.Response('a' * 64, 200));
      expect(
          () => downloadApk('https://e/a.apk',
              file: file, onProgress: (_) {}, client: client, freeBytes: () => 0),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'storage')));
    });

    test('throws networkFailure when the stream is interrupted', () async {
      final client = _FailMidStreamClient(4096);
      expect(
          () => downloadApk('https://e/a.apk',
              file: file, onProgress: (_) {}, client: client),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'network')));
    });

    test('throws malformedManifest when verifyManifest rejects the file', () async {
      final client =
          MockClient((req) async => http.Response('not-an-apk', 200));
      expect(
          () => downloadApk('https://e/a.apk',
              file: file,
              onProgress: (_) {},
              client: client,
              verifyManifest: (_) async => null),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'malformed')));
    });
  });

  group('AppUpdater.download integration', () {
    late Directory tmp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('updater_dl');
      UpdateStorage.root = () async => tmp;
    });

    tearDown(() {
      UpdateStorage.root = () => throw UnimplementedError();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('downloads an APK and verifies its embedded manifest', () async {
      final apk = await buildFixtureApk();
      final body = apk.readAsBytesSync();
      final client = MockClient((req) async => http.Response.bytes(body, 200));
      final updater = AppUpdater(
        httpClient: client,
        freeBytes: () => 1 << 30,
      );
      final release = ReleaseInfo(
        tag: 'v149',
        versionCode: 149,
        versionName: '149',
        notes: '',
        assets: [
          ApkAsset(
            name: 'app-arm64-v8a-release.apk',
            url: 'https://e/a.apk',
            sizeBytes: body.length,
            sha256: '',
          ),
        ],
        mandatory: false,
        publishedAt: null,
      );
      final downloaded = await updater.download(
        release,
        release.assets.first,
        onProgress: (_) {},
      );
      expect(downloaded.existsSync(), isTrue);
      final manifest = await readApkManifest(downloaded);
      expect(manifest, isNotNull);
      expect(manifest!.versionCode, 149);
    });

    test('throws installUnavailable when no installer is configured', () async {
      final updater = AppUpdater();
      final file = File('${tmp.path}/x.apk')..writeAsStringSync('x');
      expect(() => updater.installDownloaded(file),
          throwsA(isA<UpdateException>()
              .having((e) => e.kind, 'kind', 'install')));
    });

    test('throws installRejected when the installer fails', () async {
      final updater = AppUpdater(installer: _ThrowingInstaller());
      final file = File('${tmp.path}/x.apk')..writeAsStringSync('x');
      expect(
          () => updater.installDownloaded(file),
          throwsA(
              isA<UpdateException>().having((e) => e.kind, 'kind', 'installRejected')));
    });

    test('installDownloaded delegates to the system installer', () async {
      final installer = _RecordingInstaller();
      final updater = AppUpdater(installer: installer);
      final file = File('${tmp.path}/x.apk')..writeAsStringSync('x');
      await updater.installDownloaded(file);
      expect(installer.paths, [file.path]);
    });
  });
}

Future<UpdatePreferences> _freshPrefs() async =>
    UpdatePreferences(await SharedPreferences.getInstance());

class _ThrowingInstaller implements Installer {
  @override
  Future<void> install(String apkPath) async => throw Exception('no installer');
}

class _RecordingInstaller implements Installer {
  final List<String> paths = [];
  @override
  Future<void> install(String apkPath) async => paths.add(apkPath);
}
