import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/services/voice_note_codec.dart';

void main() {
  group('voice note content', () {
    test('encodes and decodes a storage path', () {
      const path = 'conv-1/voice/user-1/message-1.m4a';
      final content = encodeVoiceNoteContent(path);
      expect(content.startsWith('voice:'), isTrue);
      expect(decodeVoiceNotePath(content), path);
    });

    test('rejects content that is not a voice note', () {
      expect(decodeVoiceNotePath('hello there'), isNull);
    });

    test('rejects malformed and empty voice payloads', () {
      expect(decodeVoiceNotePath('voice:{not json'), isNull);
      expect(decodeVoiceNotePath('voice:{"mime":"audio/m4a"}'), isNull);
      expect(decodeVoiceNotePath('voice:{"path":""}'), isNull);
      expect(decodeVoiceNotePath('voice:[1,2,3]'), isNull);
    });
  });

  group('voice note limits', () {
    test('accepts the byte cap exactly and rejects one byte over', () {
      expect(isVoiceNoteTooLarge(maxVoiceNoteBytes), isFalse);
      expect(isVoiceNoteTooLarge(maxVoiceNoteBytes + 1), isTrue);
    });

    test('accepts the duration cap exactly and rejects one tick over', () {
      expect(isVoiceNoteTooLong(maxVoiceNoteDuration), isFalse);
      expect(isVoiceNoteTooLong(maxVoiceNoteDuration + const Duration(microseconds: 1)), isTrue);
    });
  });

  group('failure messages', () {
    test('every failure has user-facing copy', () {
      for (final failure in VoiceNoteFailure.values) {
        expect(voiceNoteFailureMessage(failure).trim(), isNotEmpty);
        expect(voiceNoteFailureMessage(failure), isNot(contains('null')));
      }
    });

    test('permission and size failures are distinct', () {
      expect(voiceNoteFailureMessage(VoiceNoteFailure.permissionDenied),
          isNot(voiceNoteFailureMessage(VoiceNoteFailure.tooLarge)));
    });
  });
}
