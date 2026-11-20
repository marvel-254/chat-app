import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/services/signal_e2ee.dart';

void main() {
  group('fail-closed E2EE contract', () {
    test('legacy plaintext is not reported as a secure envelope', () {
      expect(SignalE2ee.instance.isSecureEnvelope('good evening'), isFalse);
      expect(SignalE2ee.instance.isSecureEnvelope('[Attachment]'), isFalse);
    });

    test('sig1 envelope is recognised as secure', () {
      expect(SignalE2ee.instance.isSecureEnvelope('sig1:AAAA'), isTrue);
    });

    test('malformed envelope throws instead of returning plaintext', () async {
      expect(
        () => SignalE2ee.instance.decrypt('peer', 'sig1:not-base64!'),
        throwsA(
          isA<E2eeException>().having(
            (e) => e.reason,
            'reason',
            E2eeFailure.malformedEnvelope,
          ),
        ),
      );
    });

    test('too-short envelope is rejected as malformed', () async {
      expect(
        () => SignalE2ee.instance.decrypt('peer', 'sig1:AA=='),
        throwsA(
          isA<E2eeException>().having(
            (e) => e.reason,
            'reason',
            E2eeFailure.malformedEnvelope,
          ),
        ),
      );
    });

    test('encryption before initialisation throws, never returns input', () async {
      expect(
        () => SignalE2ee.instance.encrypt('peer', Uint8List.fromList(utf8.encode('plaintext'))),
        throwsA(isA<E2eeException>()),
      );
    });

    test('typed failures carry a stable reason name', () {
      expect(E2eeFailure.identityChanged.name, 'identityChanged');
      expect(
        const E2eeException(E2eeFailure.decryptionFailed).toString(),
        contains('decryptionFailed'),
      );
    });
  });
}
