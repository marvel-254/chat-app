import 'package:bro_chat/services/search_safety.dart';
import 'package:bro_chat/ui/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('sanitizeSearchTerm', () {
    test('keeps username characters and trims', () {
      expect(sanitizeSearchTerm('  alex.vance_1-x  '), 'alex.vance_1-x');
    });

    test('strips PostgREST filter metacharacters', () {
      expect(
        sanitizeSearchTerm('foo,id.eq.1),username.ilike.*'),
        'foo id.eq.1 username.ilike.',
      );
    });

    test('returns empty for punctuation-only input', () {
      expect(sanitizeSearchTerm(',,,(%%%)'), '');
    });

    test('caps length', () {
      expect(sanitizeSearchTerm('a' * 80).length, 64);
    });
  });

  group('friendlyErrorMessage', () {
    test('softens invalid login credentials', () {
      expect(
        friendlyErrorMessage(AuthException('Invalid login credentials')),
        "That email or password doesn't match. Double-check and try again.",
      );
    });

    test('never returns Exception prefixes or postgres guts', () {
      expect(
        friendlyErrorMessage(Exception('postgrest 42501 permission denied')),
        "You don't have access to that.",
      );
      expect(
        friendlyErrorMessage(StateError('rate limit exceeded')),
        "You're sending a bit fast. Take a breath and try again in a moment.",
      );
    });

    test('passes through already-kind copy', () {
      expect(
        friendlyErrorMessage("That email doesn't look quite right."),
        "That email doesn't look quite right.",
      );
    });

    test('maps blocked-user database errors', () {
      expect(
        friendlyErrorMessage(PostgrestException(
          message: 'cannot message this user',
          code: 'P0001',
        )),
        "You can't message this person right now.",
      );
    });

    test('falls back instead of dumping JSON', () {
      expect(
        friendlyErrorMessage('{error: true, stack: [...]}'),
        "Something didn't work. Please try again.",
      );
    });
  });
}
