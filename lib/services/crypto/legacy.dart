/// Read-only decoder for the insecure, unversioned historical format.
/// Never use participant IDs to protect new data.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

// Key stored per conversation in secure storage.
const _storageKeyPrefix = 'e2ee_key_';

/// Singleton storage instance.
FlutterSecureStorage? _storage;

FlutterSecureStorage _getStorage() {
  _storage ??= const FlutterSecureStorage();
  return _storage!;
}

// ─── Key Management ───

/// Derive a shared conversation key from two participants' user IDs using HKDF.
///
/// Uses HKDF-SHA256 over a sorted concatenation of both user IDs with a
/// protocol-specific salt for proper key separation and forward compatibility.
/// Both parties arrive at the same key without exchanging it.
String deriveSharedKey(String userIdA, String userIdB) {
  final ordered = [userIdA, userIdB]..sort();
  final seed = '$ordered[0]|$ordered[1]';
  final salt = Uint8List.fromList(utf8.encode('bro.e2ee.v1|$seed'));
  final ikm = Uint8List.fromList(utf8.encode(seed));
  final info = Uint8List.fromList(utf8.encode('conversation-key'));

  final hkdf = HKDFKeyDerivator(SHA256Digest());
  final params = HkdfParameters(ikm, 32, salt, info);
  hkdf.init(params);
  final keyBytes = Uint8List(32);
  hkdf.deriveKey(keyBytes, 0, keyBytes, 0);

  return _bytesToHex(keyBytes);
}

/// Retrieve the stored conversation key, or null if not found.
Future<String?> loadConversationKey(String conversationId) async {
  final storage = _getStorage();
  return await storage.read(key: '$_storageKeyPrefix$conversationId');
}

/// Get or derive the conversation key. Checks secure storage first, then
/// derives from user IDs using HKDF.
Future<String> getOrDeriveKey(
  String conversationId,
  String userIdA,
  String userIdB,
) async {
  final cached = await loadConversationKey(conversationId);
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }
  final derived = deriveSharedKey(userIdA, userIdB);
  // Deliberately never create new legacy storage.
  return derived;
}

// ─── Encryption / Decryption ───

/// Decrypt ciphertext from the historical writer.
///
/// Expects a base64 string: nonce (12 bytes) + ciphertext + GCM tag (16 bytes).
String? decrypt(String keyHex, String encryptedText) {
  try {
    final key = _hexToBytes(keyHex);
    final packed = base64Decode(encryptedText);

    if (packed.length < 12 + 16) {
      return null;
    }

    final nonce = packed.sublist(0, 12);
    final ciphertextWithTag = packed.sublist(12);

    final gcm = GCMBlockCipher(AESEngine());
    gcm.init(false, ParametersWithIV(KeyParameter(key), nonce));

    final plaintext = gcm.process(ciphertextWithTag);
    return utf8.decode(plaintext.toList());
  } catch (_) {
    return null;
  }
}

/// Check if a string looks like encrypted content.
bool isEncrypted(String content) {
  if (content.isEmpty) return false;
  if (content.length < 28) return false;
  try {
    final decoded = base64Decode(content);
    return decoded.length >= 28;
  } catch (_) {
    return false;
  }
}

// ─── Helpers ───

String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _hexToBytes(String hex) {
  final bytes = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}
