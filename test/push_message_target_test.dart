import 'package:bro_chat/services/push_message_target.dart';
import 'package:flutter_test/flutter_test.dart';

const conversation = 'aabbccdd-1234-1234-1234-001122334455';
const recipient = '11223344-1234-1234-1234-556677889900';

void main() {
  test('extracts the conversation and the intended account', () {
    final target = PushMessageTarget.fromData({
      'conversation_id': conversation.toUpperCase(),
      'recipient_user_id': recipient,
    });
    expect(target?.conversationId, conversation);
    expect(target?.recipientUserId, recipient);
  });

  test('accepts older payloads without treating them as account-scoped', () {
    final target =
        PushMessageTarget.fromData({'conversation_id': conversation});
    expect(target?.conversationId, conversation);
    expect(target?.recipientUserId, isNull);
  });

  test('rejects malformed routes and malformed optional recipients', () {
    expect(PushMessageTarget.fromData({}), isNull);
    expect(
        PushMessageTarget.fromData({'conversation_id': '../settings'}), isNull);
    expect(PushMessageTarget.fromData({'conversation_id': 42}), isNull);
    for (final invalid in [null, '', 42, 'someone']) {
      expect(
          PushMessageTarget.fromData({
            'conversation_id': conversation,
            'recipient_user_id': invalid,
          }),
          isNull);
    }
  });
}
