import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Checks passwords against the Have I Been Pwned (HIBP) Pwned Passwords
/// k-anonymity Range API (`https://api.pwnedpasswords.com/range/<prefix>`).
///
/// Only the first 5 hex characters of the SHA-1 hash are transmitted.
/// Fails open on network errors or timeouts so sign-up is never blocked by
/// third-party availability.
class HibpPasswordCheck {
  HibpPasswordCheck._();

  static const Duration defaultTimeout = Duration(seconds: 2);

  /// Computes the uppercase SHA-1 hex digest of [password].
  static String sha1HexUpper(String password) {
    final digest = sha1.convert(utf8.encode(password));
    return digest.toString().toUpperCase();
  }

  /// Returns `true` if [suffix] (35-char uppercase hex) appears in [body]
  /// with a breach count greater than zero.
  static bool isSuffixInRangeResponse(String body, String suffix) {
    final target = suffix.toUpperCase();
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final candidate = line.substring(0, colon).trim().toUpperCase();
      if (candidate == target) {
        final count = int.tryParse(line.substring(colon + 1).trim()) ?? 0;
        return count > 0;
      }
    }
    return false;
  }

  /// Returns `true` if [password] is found in known breaches, or `false` if
  /// not found or if the check fails/times out (fail-open).
  static Future<bool> isLeaked(
    String password, {
    http.Client? client,
    Duration timeout = defaultTimeout,
  }) async {
    if (password.isEmpty) return false;
    final hash = sha1HexUpper(password);
    final prefix = hash.substring(0, 5);
    final suffix = hash.substring(5);
    final ownsClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('https://api.pwnedpasswords.com/range/$prefix');
      final response = await httpClient.get(
        uri,
        headers: const {'Add-Padding': 'true'},
      ).timeout(timeout);
      if (response.statusCode != 200) return false;
      return isSuffixInRangeResponse(response.body, suffix);
    } catch (_) {
      return false;
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
  }
}
