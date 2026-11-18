import 'package:bro_chat/models/friendship_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FriendshipTimelineEntry', () {
    test('reads a shared photo row from the timeline RPC', () {
      final entry = FriendshipTimelineEntry.fromJson({
        'id': 'p1',
        'kind': 'photo',
        'conversation_id': 'c1',
        'created_at': '2026-11-13T10:00:00.000Z',
        'photo_path': 'c1/u1/p1.jpg',
        'photo_caption': 'Night drive',
        'photo_message_id': 'm1',
        'date_title': null,
        'occurs_on': null,
        'remind_annually': null,
        'moment_message_id': null,
        'moment_preview': null,
        'moment_pinned_at': null,
        'moment_sender_id': null,
      });

      expect(entry.isPhoto, isTrue);
      expect(entry.isDate, isFalse);
      expect(entry.photoPath, 'c1/u1/p1.jpg');
      expect(entry.photoCaption, 'Night drive');
      expect(entry.photoMessageId, 'm1');
      expect(entry.railLabel, 'Shared photo');
    });

    test('reads an important date row', () {
      final entry = FriendshipTimelineEntry.fromJson({
        'id': 'd1',
        'kind': 'date',
        'conversation_id': 'c1',
        'created_at': '2026-11-13T10:00:00.000Z',
        'photo_path': null,
        'photo_caption': null,
        'photo_message_id': null,
        'date_title': 'Maya’s birthday',
        'occurs_on': '1998-06-03',
        'remind_annually': false,
        'moment_message_id': null,
        'moment_preview': null,
        'moment_pinned_at': null,
        'moment_sender_id': null,
      });

      expect(entry.isDate, isTrue);
      expect(entry.dateTitle, 'Maya’s birthday');
      expect(entry.occursOn, DateTime(1998, 6, 3));
      expect(entry.remindAnnually, isFalse);
      expect(entry.railLabel, 'Important date');
    });

    test('reads a pinned moment and labels its sender', () {
      final entry = FriendshipTimelineEntry.fromJson({
        'id': 'm1',
        'kind': 'moment',
        'conversation_id': 'c1',
        'created_at': '2026-11-13T10:00:00.000Z',
        'photo_path': null,
        'photo_caption': null,
        'photo_message_id': null,
        'date_title': null,
        'occurs_on': null,
        'remind_annually': null,
        'moment_message_id': 'm1',
        'moment_preview': 'Remember the arcade?',
        'moment_pinned_at': '2026-11-14T09:00:00.000Z',
        'moment_sender_id': 'u1',
      });

      expect(entry.isMoment, isTrue);
      expect(entry.isFirstMessage, isFalse);
      expect(entry.momentPreview, 'Remember the arcade?');
      expect(entry.momentSenderId, 'u1');
      expect(entry.railLabel, 'Pinned moment');
    });

    test('labels the first message kind distinctly', () {
      final entry = FriendshipTimelineEntry.fromJson({
        'id': 'm0',
        'kind': 'first_message',
        'conversation_id': 'c1',
        'created_at': '2026-10-30T10:00:00.000Z',
        'moment_message_id': 'm0',
        'moment_preview': 'Hey! 👋',
        'moment_sender_id': 'u1',
      });

      expect(entry.isFirstMessage, isTrue);
      expect(entry.railLabel, 'First message');
      expect(entry.momentPinnedAt, isNull);
    });

    test('round-trips through toJson', () {
      final entry = FriendshipTimelineEntry.fromJson({
        'id': 'p1',
        'kind': 'photo',
        'conversation_id': 'c1',
        'created_at': '2026-11-13T10:00:00.000Z',
        'photo_path': 'c1/u1/p1.jpg',
      });
      final restored = FriendshipTimelineEntry.fromJson(entry.toJson());
      expect(restored.id, entry.id);
      expect(restored.kind, entry.kind);
      expect(restored.photoPath, entry.photoPath);
    });

    test('tryParse drops rows that cannot be rendered', () {
      expect(
        FriendshipTimelineEntry.tryParse({'id': '', 'created_at': 'x'}),
        isNull,
      );
      expect(
        FriendshipTimelineEntry.tryParse({'id': 'p1'}),
        isNull,
      );
      expect(
        FriendshipTimelineEntry.tryParse(
            {'created_at': '2026-11-13T10:00:00Z'}),
        isNull,
      );
      final ok = FriendshipTimelineEntry.tryParse({
        'id': 'p1',
        'kind': 'photo',
        'created_at': '2026-11-13T10:00:00.000Z',
      });
      expect(ok, isNotNull);
      expect(ok!.conversationId, '');
    });
  });

  group('FriendshipDate', () {
    test('dayLabel is short and readable', () {
      final date = FriendshipDate.fromJson({
        'id': 'd1',
        'conversation_id': 'c1',
        'title': 'Anniversary',
        'occurs_on': '2026-12-03',
        'remind_annually': true,
        'created_at': '2026-11-13T10:00:00.000Z',
      });
      expect(date.dayLabel, '3 Dec');
      expect(date.remindAnnually, isTrue);
    });
  });

  group('FriendshipPhoto', () {
    test('reads the storage path and caption', () {
      final photo = FriendshipPhoto.fromJson({
        'id': 'p1',
        'conversation_id': 'c1',
        'object_path': 'c1/u1/p1.jpg',
        'caption': 'Concert',
        'taken_from_message_id': 'm1',
        'created_at': '2026-11-13T10:00:00.000Z',
      });
      expect(photo.objectPath, 'c1/u1/p1.jpg');
      expect(photo.caption, 'Concert');
      expect(photo.takenFromMessageId, 'm1');
    });
  });
}
