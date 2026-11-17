import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bro_chat/models/pending_message.dart';
import 'package:bro_chat/services/message_outbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await MessageOutbox.load();
  });

  test('PendingMessage round-trips through JSON', () {
    final original = PendingMessage(
      localId: 'local-1',
      conversationId: 'conversation-1',
      senderId: 'sender-1',
      content: 'queued hello',
      createdAt: DateTime.parse('2026-11-17T12:00:00Z'),
      expiresAt: DateTime.parse('2026-11-18T12:00:00Z'),
      replyToId: 'message-1',
      status: 'failed',
      retryCount: 2,
    );

    final restored = PendingMessage.fromJson(original.toJson());

    expect(restored, original);
    expect(restored.content, original.content);
    expect(restored.expiresAt, original.expiresAt);
    expect(restored.replyToId, original.replyToId);
    expect(restored.status, 'failed');
    expect(restored.retryCount, 2);
  });

  test('outbox removes a message after a successful flush', () async {
    final item = PendingMessage(
      localId: 'flush-success',
      conversationId: 'conversation-success',
      senderId: 'sender-1',
      content: 'send me',
      createdAt: DateTime.now(),
      status: 'queued',
    );
    await MessageOutbox.put(item);

    var sent = false;
    await MessageOutbox.flush((value) async {
      sent = value.localId == item.localId;
    });

    expect(sent, isTrue);
    expect(MessageOutbox.forConversation('conversation-success'), isEmpty);
  });

  test('outbox preserves a failed message for retry', () async {
    final item = PendingMessage(
      localId: 'flush-failure',
      conversationId: 'conversation-failure',
      senderId: 'sender-1',
      content: 'try again',
      createdAt: DateTime.now(),
      status: 'queued',
    );
    await MessageOutbox.put(item);

    await MessageOutbox.flush((_) async {
      throw StateError('offline');
    });

    final remaining = MessageOutbox.forConversation('conversation-failure');
    expect(remaining, hasLength(1));
    expect(remaining.single.status, 'failed');
    expect(remaining.single.retryCount, 1);
  });
}
