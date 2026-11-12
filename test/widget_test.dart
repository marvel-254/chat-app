import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/models/profile.dart';

void main() {
  test('Conversation reads the latest-message fields from its RPC row', () {
    final conversation = Conversation.fromJson({
      'id': 'conversation-1',
      'created_at': '2026-10-30T10:00:00.000Z',
      'updated_at': '2026-10-30T10:05:00.000Z',
      'peer_username': 'maya',
      'peer_display_name': 'Maya',
      'last_message': 'See you soon',
      'last_message_at': '2026-10-30T10:05:00.000Z',
      'unread_count': 1,
    });

    expect(conversation.lastMessage, 'See you soon');
    expect(conversation.lastMessageAt, DateTime.utc(2026, 10, 30, 10, 5));
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

  test('Message exposes deletion state so the UI can render a tombstone', () {
    final message = Message.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'content': 'This message was deleted',
      'created_at': '2026-11-12T10:00:00.000Z',
      'deleted_at': '2026-11-12T10:05:00.000Z',
    });

    expect(message.deletedAt, DateTime.utc(2026, 11, 12, 10, 5));
  });

  test('Conversation defaults isLocked to false for older RPC payloads', () {
    final conversation = Conversation.fromJson({
      'id': 'conversation-2',
      'created_at': '2026-10-30T10:00:00.000Z',
      'updated_at': '2026-10-30T10:05:00.000Z',
      'unread_count': 0,
    });

    expect(conversation.isLocked, isFalse);
    expect(conversation.peerId, isNull);
  });
}
