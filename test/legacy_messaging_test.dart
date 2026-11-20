import 'package:bro_chat/services/legacy_message_codec.dart';
import 'package:bro_chat/services/legacy_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LegacyMessaging.reset);

  test('only explicit session consent enables server-readable writes', () {
    expect(() => LegacyMessaging.requireAllowed('alice'), throwsStateError);
    LegacyMessaging.allow('alice');
    expect(LegacyMessaging.allowed('alice'), isTrue);
    expect(LegacyMessaging.allowed('bob'), isFalse);
    LegacyMessaging.reset();
    expect(LegacyMessaging.allowed('alice'), isFalse);
  });

  test(
      'legacy decoding preserves ambiguous old content and never decodes new plaintext',
      () {
    const fixture = 'AAAAAAAAAAAAAAAAK7dEY+ijvwZGF5ArQQ59xKHPyz38/6OedJjMFA==';
    final correct = LegacyMessageCodec.historicalKey('bob', 'alice');
    final wrong = LegacyMessageCodec.historicalKey('bob', 'carol');
    expect(
        LegacyMessageCodec.display(
            fixture, LegacyMessageCodec.unversioned, correct),
        'legacy hello');
    expect(
        LegacyMessageCodec.display(
            fixture, LegacyMessageCodec.unversioned, wrong),
        fixture);
    expect(
        LegacyMessageCodec.display(
            fixture, LegacyMessageCodec.plaintext, correct),
        fixture);
    expect(
        LegacyMessageCodec.display(
            'not valid ciphertext', LegacyMessageCodec.unversioned, correct),
        'not valid ciphertext');
    expect(LegacyMessageCodec.display('not exposed', 'unknown', correct),
        'Unsupported message format');
  });
}
