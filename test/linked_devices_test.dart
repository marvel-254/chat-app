import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/models/linked_device.dart';

void main() {
  test('LinkedDevice parses registry rows and identifies the current device',
      () {
    final device = LinkedDevice.fromJson({
      'id': 'row-1',
      'device_id': 'install-1',
      'device_name': 'Pixel 9',
      'platform': 'Android',
      'created_at': '2026-11-17T08:00:00.000Z',
      'last_seen_at': '2026-11-17T09:30:00.000Z',
      'revoked_at': null,
    }, currentDeviceId: 'install-1');

    expect(device.id, 'row-1');
    expect(device.deviceId, 'install-1');
    expect(device.deviceName, 'Pixel 9');
    expect(device.platform, 'Android');
    expect(device.isCurrent, isTrue);
    expect(device.revokedAt, isNull);
  });

  test('LinkedDevice marks another active device as not current', () {
    final device = LinkedDevice.fromJson({
      'id': 'row-2',
      'device_id': 'install-2',
      'device_name': 'Chrome on Mac',
      'platform': 'Web',
      'created_at': '2026-11-16T08:00:00.000Z',
      'last_seen_at': '2026-11-17T07:00:00.000Z',
    }, currentDeviceId: 'install-1');

    expect(device.isCurrent, isFalse);
    expect(device.isRevoked, isFalse);
  });

  test(
      'linked device timestamps stay readable across recent and older activity',
      () {
    final now = DateTime.utc(2026, 11, 17, 12, 0);

    expect(
      formatLinkedDeviceTimestamp(
        now.subtract(const Duration(seconds: 20)),
        now: now,
      ),
      'Just now',
    );
    expect(
      formatLinkedDeviceTimestamp(
        now.subtract(const Duration(minutes: 12)),
        now: now,
      ),
      '12m ago',
    );
    expect(
      formatLinkedDeviceTimestamp(
        now.subtract(const Duration(hours: 3)),
        now: now,
      ),
      '3h ago',
    );
    expect(
      formatLinkedDeviceTimestamp(
        DateTime.utc(2026, 11, 10, 12),
        now: now,
      ),
      'Nov 10, 2026',
    );
  });
}
