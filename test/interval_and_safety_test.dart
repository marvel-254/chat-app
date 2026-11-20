import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/services/message_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Postgres interval parsing', () {
    test('handles the formats Supabase returns for message expiry', () {
      expect(parseInterval('00:00:00'), isNull);
      expect(parseInterval('0 seconds'), isNull);
      expect(parseInterval('01:00:00'), const Duration(hours: 1));
      expect(parseInterval('1 day'), const Duration(days: 1));
      expect(parseInterval('30 days'), const Duration(days: 30));
      expect(parseInterval('unexpected'), isNull);
    });
  });

  group('message validation', () {
    test('rejects empty, oversized and shortened-link messages', () {
      expect(MessageSafety.validateContent('   '),
          contains('Write a little something'));
      expect(MessageSafety.validateContent('a' * 4001), contains('shortening'));
      expect(MessageSafety.validateContent('read this: https://bit.ly/abc'),
          contains('unsafe'));
    });
  });
}
