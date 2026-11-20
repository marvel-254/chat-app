import 'dart:typed_data';
import 'package:bro_chat/services/crypto/attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('files use independent random keys; reject malformed and modified bytes',
      () {
    final bytes = Uint8List.fromList([0, 255, 65, 0]);
    final first = AttachmentCipher.seal(bytes),
        second = AttachmentCipher.seal(bytes);
    expect(first.key, isNot(second.key));
    expect(first.bytes, isNot(orderedEquals(second.bytes)));
    expect(AttachmentCipher.open(first.bytes, first.key), orderedEquals(bytes));
    expect(() => AttachmentCipher.open(first.bytes, second.key),
        throwsA(anything));
    first.bytes.last ^= 1;
    expect(
        () => AttachmentCipher.open(first.bytes, first.key), throwsA(anything));
    expect(() => AttachmentCipher.open(Uint8List(8), first.key),
        throwsFormatException);
  });
}
