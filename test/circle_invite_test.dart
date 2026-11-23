import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/models/circle.dart';

void main() {
  group('CircleInvite.fromJson', () {
    test('maps RPC columns and falls back on missing values', () {
      final invite = CircleInvite.fromJson({
        'invite_id': 'invite-1',
        'circle_id': 'circle-1',
        'circle_name': 'Studio Circle',
        'avatar_path': 'avatars/studio.png',
        'inviter_name': 'Alice',
        'created_at': '2026-11-23T08:00:00.000Z',
      });
      expect(invite.id, 'invite-1');
      expect(invite.circleId, 'circle-1');
      expect(invite.circleName, 'Studio Circle');
      expect(invite.avatarPath, 'avatars/studio.png');
      expect(invite.inviterName, 'Alice');
      expect(invite.createdAt.toUtc().hour, 8);
    });

    test('missing rows never produce empty identifiers in the UI', () {
      final invite = CircleInvite.fromJson({});
      expect(invite.id, '');
      expect(invite.inviterName, 'Someone');
      expect(invite.createdAt, isA<DateTime>());
    });
  });
}
