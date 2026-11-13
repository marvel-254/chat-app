import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/services/status_feed.dart';
import 'package:flutter_test/flutter_test.dart';

StatusPost _post({
  required String id,
  required String userId,
  required DateTime created,
  String? name,
}) {
  return StatusPost(
    id: id,
    userId: userId,
    content: 'hello $id',
    createdAt: created,
    expiresAt: created.add(const Duration(hours: 24)),
    userDisplayName: name,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 11, 13, 10);

  test('StatusPost.fromJson reads nested profile', () {
    final post = StatusPost.fromJson({
      'id': 's1',
      'user_id': 'u1',
      'content': 'night out',
      'media_path': null,
      'mood': '🔥',
      'privacy': 'followers',
      'created_at': '2026-11-13T10:00:00.000Z',
      'expires_at': '2026-11-14T10:00:00.000Z',
      'profiles': {
        'username': 'maya',
        'display_name': 'Maya',
        'avatar_url': 'https://example/a.png',
      },
    });
    expect(post.userLabel, 'Maya');
    expect(post.userInitial, 'M');
    expect(post.hasText, isTrue);
    expect(post.hasMedia, isFalse);
    expect(post.mood, '🔥');
    expect(post.privacy, 'followers');
  });

  test('groupStatusFeed puts me first and sorts others by latest', () {
    final posts = [
      _post(id: 'a1', userId: 'peer-a', created: t0, name: 'A'),
      _post(
          id: 'me1',
          userId: 'me',
          created: t0.add(const Duration(minutes: 1)),
          name: 'Me'),
      _post(
          id: 'b1',
          userId: 'peer-b',
          created: t0.add(const Duration(minutes: 5)),
          name: 'B'),
      _post(
          id: 'a2',
          userId: 'peer-a',
          created: t0.add(const Duration(minutes: 2)),
          name: 'A'),
    ];
    final threads = groupStatusFeed(posts, 'me');
    expect(threads.map((t) => t.userId).toList(), ['me', 'peer-b', 'peer-a']);
    expect(threads.first.count, 1);
    expect(threads.last.posts.map((p) => p.id).toList(), ['a1', 'a2']);
  });

  test('statusTimeAgo and time left', () {
    final now = DateTime.utc(2026, 11, 13, 12);
    expect(statusTimeAgo(now.subtract(const Duration(seconds: 10)), now),
        'just now');
    expect(statusTimeAgo(now.subtract(const Duration(minutes: 12)), now),
        '12m ago');
    expect(
        statusTimeAgo(now.subtract(const Duration(hours: 3)), now), '3h ago');
    expect(statusTimeLeft(now.add(const Duration(hours: 9)), now), '9h left');
    expect(statusTimeLeft(now.subtract(const Duration(minutes: 1)), now),
        'expired');
  });

  test('privacy labels', () {
    expect(statusPrivacyLabel('everyone'), 'Everyone');
    expect(statusPrivacyLabel('followers'), 'Followers');
    expect(statusPrivacyLabel('contacts'), 'Contacts');
  });
}
