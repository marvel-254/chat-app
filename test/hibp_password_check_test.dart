import 'package:bro_chat/services/hibp_password_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HibpPasswordCheck', () {
    test('sha1HexUpper computes standard uppercase SHA-1', () {
      expect(
        HibpPasswordCheck.sha1HexUpper('password'),
        '5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8',
      );
    });

    test('isSuffixInRangeResponse matches non-zero breach counts', () {
      const body = '1E4C9B93F3F0682250B6CF8331B7EE68FD8:3861493\r\n'
          '00000000000000000000000000000000000:0\r\n';
      expect(
        HibpPasswordCheck.isSuffixInRangeResponse(
          body,
          '1e4c9b93f3f0682250b6cf8331b7ee68fd8',
        ),
        isTrue,
      );
      expect(
        HibpPasswordCheck.isSuffixInRangeResponse(
          body,
          '00000000000000000000000000000000000',
        ),
        isFalse,
      );
      expect(
        HibpPasswordCheck.isSuffixInRangeResponse(
          body,
          'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        ),
        isFalse,
      );
    });

    test('isLeaked sends only 5-char prefix and detects leaked password',
        () async {
      late Uri requestedUri;
      final client = MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          '1E4C9B93F3F0682250B6CF8331B7EE68FD8:42\n',
          200,
        );
      });

      final leaked = await HibpPasswordCheck.isLeaked(
        'password',
        client: client,
      );

      expect(leaked, isTrue);
      expect(requestedUri.path, '/range/5BAA6');
    });

    test('isLeaked fails open on HTTP errors and timeouts', () async {
      final serverErrorClient = MockClient(
        (_) async => http.Response('err', 503),
      );
      expect(
        await HibpPasswordCheck.isLeaked(
          'password',
          client: serverErrorClient,
        ),
        isFalse,
      );

      final slowClient = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('', 200);
      });
      expect(
        await HibpPasswordCheck.isLeaked(
          'password',
          client: slowClient,
          timeout: const Duration(milliseconds: 20),
        ),
        isFalse,
      );
    });
  });
}
