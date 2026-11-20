import 'package:bro_chat/services/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release version comparison', () {
    test('understands release tags and pubspec versions', () {
      expect(AppUpdate.parseVersion('v1.4.5'), [1, 4, 5]);
      expect(AppUpdate.parseVersion('1.4.5+21'), [1, 4, 5]);
      expect(AppUpdate.parseVersion(''), isNull);
      expect(AppUpdate.parseVersion('v1.4'), [1, 4, 0]);
    });

    test('promotes real releases but not same or older builds', () {
      expect(AppUpdate.isNewer('v1.4.6', '1.4.5'), isTrue);
      expect(AppUpdate.isNewer('v2.0.0', '1.9.9'), isTrue);
      expect(AppUpdate.isNewer('v1.4.5', '1.4.5'), isFalse);
      expect(AppUpdate.isNewer('v1.4.4', '1.4.5'), isFalse);
      expect(AppUpdate.isNewer('v1.4.5', ''), isFalse);
    });
  });

  group('APK verification', () {
    final apkHeader = <int>[0x50, 0x4b, 0x03, 0x04];
    const digest =
        'sha256:8dcc7e601606217f3b754766511182a916b17e9a26a94c9d887104eba92e9bb2';

    test('accepts a verified APK', () {
      expect(AppUpdate.verifyDigest(apkHeader, digest), isNull);
      expect(AppUpdate.verifyDigest(apkHeader, null), isNull);
    });

    test('rejects HTML pages and digest mismatches', () {
      final zeros = List.filled(64, '0').join();
      final badDigest = 'sha256:$zeros';
      expect(AppUpdate.verifyDigest(<int>[0x3c, 0x21, 0x44, 0x4f], digest),
          contains('not an Android package'));
      expect(AppUpdate.verifyDigest(apkHeader, badDigest),
          contains('checksum'));
    });
  });
}
