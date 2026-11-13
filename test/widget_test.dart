import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/services/presence.dart';

void main() {
  test('Conversation reads the latest-message fields from its RPC row', () {
    final conversation = Conversation.fromJson({
      'id': 'conversation-1',
      'created_at': '2026-10-30T10:00:00.000Z',
      'updated_at': '2026-10-30T10:05:00.000Z',
      'peer_id': 'user-maya',
      'peer_username': 'maya',
      'peer_display_name': 'Maya',
      'peer_avatar_url': 'https://example/maya.png',
      'last_message': 'See you soon',
      'last_message_at': '2026-10-30T10:05:00.000Z',
      'unread_count': 1,
    });

    expect(conversation.lastMessage, 'See you soon');
    expect(conversation.lastMessageAt, DateTime.utc(2026, 10, 30, 10, 5));
    expect(conversation.peerId, 'user-maya');
    expect(conversation.toPeerProfile()?.avatarUrl, 'https://example/maya.png');
    expect(conversation.toPeerProfile()?.label, 'Maya');
  });
  
  test('Profile parses autoLockTimer correctly', () {
    final profile = Profile.fromJson({
      'id': 'user-1',
      'username': 'testuser',
      'display_name': 'Test User',
      'avatar_url': null,
      'chat_background': 'default',
      'chat_background_image_path': null,
      'created_at': '2026-10-30T10:00:00.000Z',
      'updated_at': '2026-10-30T10:00:00.000Z',
      'about': 'Test bio',
      'photo_visibility': 'everyone',
      'status_visibility': 'everyone',
      'about_visibility': 'everyone',
      'last_seen_at': '2026-10-30T10:00:00.000Z',
      'read_receipts_enabled': true,
      'default_message_expiry': '1 day',
      'auto_lock_timer': '00:05:00',  // format: HH:MM:SS
    });
    
    expect(profile.autoLockTimer, const Duration(minutes: 5));
  });

  test('formatPresenceLabel treats a fresh ping as online', () {
    final now = DateTime.utc(2026, 11, 13, 12, 0);
    expect(
      formatPresenceLabel(now.subtract(const Duration(seconds: 20)), now: now),
      'online',
    );
    expect(
      formatPresenceLabel(now.subtract(const Duration(seconds: 50)), now: now),
      'last seen just now',
    );
    expect(
      formatPresenceLabel(now.subtract(const Duration(minutes: 8)), now: now),
      'last seen 8m ago',
    );
  });
}
