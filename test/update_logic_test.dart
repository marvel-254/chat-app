import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyx_chat/services/update_logic.dart';

void main() {
  group('VersionParser', () {
    test('parses a bare integer version code', () {
      expect(VersionParser.toCode('149'), 149);
    });

    test('parses leading v tag', () {
      expect(VersionParser.toCode('v149'), 149);
    });

    test('strips a text prefix before the number', () {
      expect(VersionParser.toCode('PreFix 149'), 149);
    });

    test('returns null for non-version strings', () {
      expect(VersionParser.toCode(null), isNull);
      expect(VersionParser.toCode(''), isNull);
      expect(VersionParser.toCode('   '), isNull);
      expect(VersionParser.toCode('release-candidate'), isNull);
      expect(VersionParser.toCode('abc'), isNull);
    });

    test('returns null for a version with no digits', () {
      expect(VersionParser.toCode('one-two-three'), isNull);
    });

    test('fromTag extracts trailing integer', () {
      expect(VersionParser.fromTag('v149'), 149);
      expect(VersionParser.fromTag('v1.0.0+149'), 149);
      expect(VersionParser.fromTag('no-number'), isNull);
    });
  });

  group('ApkAsset', () {
    const asset = ApkAsset(
      name: 'app-arm64-v8a-release.apk',
      url: 'https://example.com/a.apk',
      sizeBytes: 5 * 1024 * 1024,
      sha256: 'abc',
    );

    test('sizeLabel formats MB', () {
      expect(asset.sizeLabel, '5.0 MB');
    });

    test('sizeLabel formats KB', () {
      const k = ApkAsset(
        name: 'a.apk',
        url: 'u',
        sizeBytes: 512,
        sha256: '',
      );
      expect(k.sizeLabel, '512 B');
      const kb = ApkAsset(
        name: 'a.apk',
        url: 'u',
        sizeBytes: 1024,
        sha256: '',
      );
      expect(kb.sizeLabel, '1 KB');
    });

    test('sizeLabel handles unknown size', () {
      const z = ApkAsset(
        name: 'a.apk',
        url: 'u',
        sizeBytes: 0,
        sha256: '',
      );
      expect(z.sizeLabel, 'unknown size');
    });

    test('hasChecksum reflects sha256 presence', () {
      expect(asset.hasChecksum, isTrue);
      const none = ApkAsset(name: 'a.apk', url: 'u', sizeBytes: 1, sha256: '');
      expect(none.hasChecksum, isFalse);
    });
  });

  group('ApkSelector', () {
    List<ApkAsset> assets() => const [
          ApkAsset(
            name: 'app-arm64-v8a-release.apk',
            url: 'https://e/arm64',
            sizeBytes: 100,
            sha256: '',
          ),
          ApkAsset(
            name: 'app-armeabi-v7a-release.apk',
            url: 'https://e/armv7',
            sizeBytes: 90,
            sha256: '',
          ),
          ApkAsset(
            name: 'app-x86_64-release.apk',
            url: 'https://e/x86',
            sizeBytes: 80,
            sha256: '',
          ),
        ];

    test('selects exact ABI match for arm64-v8a', () {
      final selected = ApkSelector.select(assets(), ApkAbi.arm64V8a);
      expect(selected, isNotNull);
      expect(selected!.name, contains('arm64-v8a'));
    });

    test('selects exact ABI match for armv7', () {
      final selected = ApkSelector.select(assets(), ApkAbi.armeabiV7a);
      expect(selected, isNotNull);
      expect(selected!.name, contains('armeabi-v7a'));
    });

    test('selects exact ABI match for x86_64', () {
      final selected = ApkSelector.select(assets(), ApkAbi.x8664);
      expect(selected, isNotNull);
      expect(selected!.name, contains('x86_64'));
    });

    test('falls back to an untagged universal APK', () {
      const universal = [
        ApkAsset(name: 'app-release.apk', url: 'https://e/u', sizeBytes: 1, sha256: ''),
      ];
      final selected = ApkSelector.select(universal, ApkAbi.arm64V8a);
      expect(selected, isNotNull);
      expect(selected!.name, 'app-release.apk');
    });

    test('prefers exact ABI over untagged fallback', () {
      final mixed = [
        const ApkAsset(
            name: 'app-release.apk', url: 'https://e/u', sizeBytes: 1, sha256: ''),
        ...assets(),
      ];
      final selected = ApkSelector.select(mixed, ApkAbi.x8664);
      expect(selected!.name, contains('x86_64'));
    });

    test('returns null for an empty list', () {
      expect(ApkSelector.select(const [], ApkAbi.arm64V8a), isNull);
    });
  });

  group('ReleaseInfo.selectFor', () {
    test('returns the asset matching the device ABI', () {
      const release = ReleaseInfo(
        tag: 'v149',
        versionCode: 149,
        versionName: '149',
        notes: '',
        assets: [
          ApkAsset(
            name: 'app-arm64-v8a-release.apk',
            url: 'https://e/arm64',
            sizeBytes: 100,
            sha256: '',
          ),
        ],
        mandatory: false,
        publishedAt: null,
      );
      final selected = release.selectFor(ApkAbi.arm64V8a);
      expect(selected, isNotNull);
      expect(selected!.name, 'app-arm64-v8a-release.apk');
    });
  });

  group('ApkAssetParser.fromApi', () {
    test('extracts apk assets and skips non-apk', () {
      final parsed = ApkAssetParser.fromApi([
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://e/arm64',
          'size': 12345,
        },
        {'name': 'readme.txt', 'browser_download_url': 'https://e/r', 'size': 5},
        'not-a-map',
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.first.name, 'app-arm64-v8a-release.apk');
      expect(parsed.first.sizeBytes, 12345);
    });

    test('tolerates missing size and empty url', () {
      final parsed = ApkAssetParser.fromApi([
        {'name': 'app-x86_64-release.apk', 'browser_download_url': 'https://e/x'},
        {'name': 'app-v7.apk'},
        {'name': 'app-v8.apk', 'browser_download_url': ''},
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.first.sizeBytes, 0);
    });
  });

  group('UpdatePolicy.decide (version comparison)', () {
    const policy = UpdatePolicy();

    test('no update when remote is older than installed', () {
      final d = policy.decide(
        installedVersionCode: 200,
        remoteVersionCode: 149,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.none);
      expect(d.isUpdate, isFalse);
    });

    test('no update when versions are equal', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 149,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.none);
    });

    test('optional when a newer release is within the window', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 151,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.optional);
      expect(d.isUpdate, isTrue);
    });

    test('mandatory when the release is marked mandatory', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 150,
        releaseMandatory: true,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.mandatory);
    });

    test('mandatory when version jump exceeds the optional window', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 156,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.mandatory);
    });

    test('exactly the window boundary is still optional', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 154,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.optional);
    });

    test('postponed reminder suppresses an optional update', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 151,
        releaseMandatory: false,
        remindedToSkip: true,
      );
      expect(d.priority, UpdatePriority.none);
    });

    test('reminder does not suppress a mandatory release', () {
      final d = policy.decide(
        installedVersionCode: 149,
        remoteVersionCode: 151,
        releaseMandatory: true,
        remindedToSkip: true,
      );
      expect(d.priority, UpdatePriority.mandatory);
    });

    test('custom optionalWindow narrows or widens the jump threshold', () {
      const strict = UpdatePolicy(optionalWindow: 2);
      final d = strict.decide(
        installedVersionCode: 149,
        remoteVersionCode: 152,
        releaseMandatory: false,
        remindedToSkip: false,
      );
      expect(d.priority, UpdatePriority.mandatory);
    });
  });

  group('ManifestParser', () {
    test('parses a real AAPT binary manifest', () async {
      final bytes = await File('test/fixtures/real_manifest.bin').readAsBytes();
      final info = ManifestParser.parse(bytes);
      expect(info, isNotNull);
      expect(info!.versionCode, 149);
      expect(info.versionName, '1.0.0 (149)');
      expect(info.packageName, 'com.omixsystems.pulsechat');
    });

    test('returns null for an empty byte array', () {
      expect(ManifestParser.parse(Uint8List(0)), isNull);
    });

    test('returns null for a truncated manifest', () async {
      final bytes = await File('test/fixtures/real_manifest.bin').readAsBytes();
      expect(ManifestParser.parse(bytes.sublist(0, 40)), isNull);
    });

    test('returns null for garbage bytes', () {
      final noise = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 7 + 3) & 0xFF),
      );
      expect(ManifestParser.parse(noise), isNull);
    });

    test('returns null for bytes with a wrong top header', () {
      final noise = Uint8List.fromList(List<int>.filled(64, 0xAB));
      expect(ManifestParser.parse(noise), isNull);
    });

    test('returns null for a manifest missing the manifest element', () async {
      final bytes = await File('test/fixtures/real_manifest.bin').readAsBytes();
      expect(ManifestParser.parse(bytes.sublist(0, 100)), isNull);
    });
  });
}
