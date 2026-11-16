/// End-to-end encryption service.
///
/// Uses AES-256-GCM for symmetric message encryption. Each conversation has a
/// shared secret derived deterministically from both participants' user IDs
/// with HKDF-SHA256 for proper key separation.
/// Keys are cached locally via [flutter_secure_storage].
///
/// Protocol:
/// 1. On first open of a conversation, derive the shared key from user IDs.
/// 2. Encrypt plaintext → ciphertext (base64) before sending.
/// 3. Decrypt ciphertext → plaintext after receiving.
/// 4. If no key is available or decryption fails, fall back to plaintext
///    (for backward compat with existing messages).
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

/// Generate a random 256-bit AES key and return it as a hex string.
String generateKeyHex() {
  final bytes = SecureRandom().nextBytes(32);
  return _bytesToHex(bytes);
}

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

/// Store the conversation key in secure storage.
Future<void> storeConversationKey(String conversationId, String keyHex) async {
  final storage = _getStorage();
  await storage.write(
    key: '$_storageKeyPrefix$conversationId',
    value: keyHex,
  );
}

/// Retrieve the stored conversation key, or null if not found.
Future<String?> loadConversationKey(String conversationId) async {
  final storage = _getStorage();
  return await storage.read(key: '$_storageKeyPrefix$conversationId');
}

/// Delete the stored conversation key (for key rotation).
Future<void> deleteConversationKey(String conversationId) async {
  final storage = _getStorage();
  await storage.delete(key: '$_storageKeyPrefix$conversationId');
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
  await storeConversationKey(conversationId, derived);
  return derived;
}

// ─── Encryption / Decryption ───

/// Encrypt plaintext with AES-256-GCM using the given key hex.
///
/// Returns a base64 string: nonce (12 bytes) + ciphertext + GCM tag (16 bytes).
String encrypt(String keyHex, String plaintext) {
  final key = _hexToBytes(keyHex);
  final nonce = SecureRandom().nextBytes(12);

  final gcm = GCMBlockCipher(AESEngine());
  gcm.init(true, ParametersWithIV(KeyParameter(key), nonce));

  final input = Uint8List.fromList(utf8.encode(plaintext));
  final ciphertextWithTag = gcm.process(input);

  // Pack: nonce (12) + ciphertext (includes tag appended by GCM)
  final packed = Uint8List(nonce.length + ciphertextWithTag.length);
  packed.setAll(0, nonce);
  packed.setAll(nonce.length, ciphertextWithTag);

  return base64Encode(packed);
}

/// Decrypt ciphertext produced by [encrypt].
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