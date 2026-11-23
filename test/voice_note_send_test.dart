import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/models/pending_message.dart';
import 'package:bro_chat/services/voice_note_send.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 10);

  VoiceNoteOutcome success() =>
      VoiceNoteOutcome.success('conv-1/voice/user-1/message-1.m4a');

  test('successful outcome carries encoded voice content', () {
    final outcome = success();
    expect(outcome.isSuccess, isTrue);
    expect(outcome.content,
        contains('voice:{"path":"conv-1/voice/user-1/message-1.m4a"'));
  });

  test('failed outcome has no content to enqueue', () {
    final outcome =
        VoiceNoteOutcome.failed(VoiceNoteFailure.uploadFailed);
    expect(outcome.isSuccess, isFalse);
    expect(outcome.content, isNull);
  });

  test('pending message uses voice content and outbox defaults', () {
    final pending = voiceNotePendingMessage(
      outcome: success(),
      conversationId: 'conv-1',
      senderId: 'user-1',
      localId: 'local-1',
      now: now,
      expiry: const Duration(hours: 1),
    );

    expect(pending.localId, 'local-1');
    expect(pending.conversationId, 'conv-1');
    expect(pending.senderId, 'user-1');
    expect(pending.content, success().content);
    expect(pending.status, 'sending');
    expect(pending.expiresAt, now.add(const Duration(hours: 1)));
  });

  test('pending voice message survives outbox serialisation', () {
    final pending = voiceNotePendingMessage(
      outcome: success(),
      conversationId: 'conv-1',
      senderId: 'user-1',
      localId: 'local-1',
      now: now,
    );

    final restored = PendingMessage.fromJson(pending.toJson());
    expect(restored.content, pending.content);
    expect(restored.conversationId, 'conv-1');
  });
}
