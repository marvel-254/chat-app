// Read-only recovery of unversioned BRO messages. Participant IDs are public
// inputs, so successful decoding does NOT authenticate the author or imply E2EE.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class LegacyMessageCodec {
  static const plaintext = 'legacy_plaintext';
  static const unversioned = 'legacy_unversioned';
  static const signal = 'signal_v1';

  static Uint8List historicalKey(String first, String second) {
    final ordered = [first, second]..sort();
    // Preserve the exact interpolation used in released clients: Dart printed
    // the entire List in both halves and appended the literal [0] and [1].
    final seed = '$ordered[0]|$ordered[1]';
    final derive = HKDFKeyDerivator(SHA256Digest());
    derive.init(HkdfParameters(
      Uint8List.fromList(utf8.encode(seed)),
      32,
      Uint8List.fromList(utf8.encode('bro.e2ee.v1|$seed')),
      Uint8List.fromList(utf8.encode('conversation-key')),
    ));
    final key = Uint8List(32);
    // The old call passed the same zeroed buffer as HKDF input and output.
    derive.deriveKey(key, 0, key, 0);
    return key;
  }

  static String display(
      String content, String format, Uint8List? historicalKey) {
    if (format == plaintext) return content;
    if (format != unversioned) return 'Unsupported message format';
    if (historicalKey == null ||
        content.length < 38 ||
        content.length > 100000) {
      return content;
    }
    try {
      final packed = base64Decode(content);
      if (packed.length < 28) return content;
      final gcm = GCMBlockCipher(AESEngine());
      gcm.init(false,
          ParametersWithIV(KeyParameter(historicalKey), packed.sublist(0, 12)));
      return utf8.decode(gcm.process(packed.sublist(12)));
    } catch (_) {
      // Old rows had no format marker. A base64-looking value could be genuine
      // historical plaintext. Do not discard it or report it as secure.
      return content;
    }
  }
}
