import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/services/search_safety.dart';
import 'package:bro_chat/services/supabase.dart' show Supa;
import 'package:bro_chat/ui/errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('sanitizeSearchTerm', () {
    test('keeps username characters and trims', () {
      expect(sanitizeSearchTerm('  alex.vance_1-x  '), 'alex.vance_1-x');
    });

    test('normalizes a leading username at-sign', () {
      expect(sanitizeSearchTerm('@alex.vance'), 'alex.vance');
    });

    test('collapses repeated spaces and line breaks', () {
      expect(sanitizeSearchTerm('  Alex  \t Vance\n Jr.  '), 'Alex Vance Jr.');
    });

    test('returns empty for a bare username prefix', () {
      expect(sanitizeSearchTerm('  @  '), '');
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

  test('exact and prefix username matches rank above other matches', () {
    Profile profile(String id, String username) => Profile.fromJson({
          'id': id,
          'username': username,
          'created_at': '2026-11-18T00:00:00Z',
          'updated_at': '2026-11-18T00:00:00Z',
        });
    final other = profile('1', 'amy_alex');
    final prefix = profile('2', 'Alex_1');
    final exact = profile('3', 'alex');
    final results = [other, prefix, exact, prefix, exact];

    expect(rankPeopleSearchResults(results, 'alex', limit: 3),
        [exact, prefix, other]);
    expect(rankPeopleSearchResults(results, 'alex', limit: 2), [exact, prefix]);
  });

  test('a bare @ does not require a network lookup or list profiles', () async {
    expect(await Supa.searchUsers('@'), isEmpty);
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

    test('maps schema-cache writes to missing columns', () {
      expect(
        friendlyErrorMessage(PostgrestException(
          message:
              "Could not find the 'peer_avatar_url' column of 'conversation_participants' in the schema cache",
          code: 'PGRST204',
        )),
        "That didn't land cleanly. Try once more.",
      );
    });

    test('hides raw postgres syntax errors', () {
      expect(
        friendlyErrorMessage(
            PostgrestException(
              message: 'invalid input syntax for type uuid: "e2e_355cbb"',
              code: '22P02',
            ),
            fallback: 'Give it another try.'),
        'Give it another try.',
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
