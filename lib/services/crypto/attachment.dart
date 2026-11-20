import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// One independent random AES-256-GCM content key per object. The signed
/// OpenPGP payload protects its key, object reference, name, MIME and size.
class AttachmentCipher {
  static Uint8List _random(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }

  static ({Uint8List bytes, String key}) seal(Uint8List plain) {
    final key = _random(32), nonce = _random(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    final payload = cipher.process(plain);
    final packed = Uint8List(nonce.length + payload.length)
      ..setAll(0, nonce)
      ..setAll(nonce.length, payload);
    return (bytes: packed, key: base64Encode(key));
  }

  static Uint8List open(Uint8List bytes, String secret) {
    final key = base64Decode(secret);
    if (key.length != 32 || bytes.length < 28)
      throw const FormatException('Invalid file');
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
          false,
          AEADParameters(
              KeyParameter(key), 128, bytes.sublist(0, 12), Uint8List(0)));
    return cipher.process(bytes.sublist(12));
  }
}
