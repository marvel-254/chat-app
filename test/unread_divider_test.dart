import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/chat/widgets.dart';
import 'package:bro_chat/models/profile.dart';

Message message(
  String id, {
  required String senderId,
  DateTime? readAt,
}) {
  return Message(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    content: 'Hello',
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    readAt: readAt,
  );
}

void main() {
  test('finds first unread inbound message', () {
    final messages = [
      message('read', senderId: 'peer', readAt: DateTime.now()),
      message('mine', senderId: 'me'),
      message('first-unread', senderId: 'peer'),
      message('later-unread', senderId: 'peer'),
    ];

    expect(
      firstUnreadInboundMessageId(messages, 'me'),
      'first-unread',
    );
  });

  test('returns null when every inbound message was read', () {
    final messages = [
      message('read', senderId: 'peer', readAt: DateTime.now()),
      message('mine', senderId: 'me'),
    ];

    expect(firstUnreadInboundMessageId(messages, 'me'), isNull);
  });

  testWidgets('renders the unread divider label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UnreadDivider()));

    expect(find.text('NEW MESSAGES'), findsOneWidget);
  });
}
