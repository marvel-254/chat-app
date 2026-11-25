import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/screens/auth/auth_validation.dart';

void main() {
  group('validateEmail', () {
    test('accepts normal addresses', () {
      expect(validateEmail('bro@example.com'), isNull);
      expect(validateEmail('  a.b+tag@sub.domain.co  '), isNull);
    });

    test('rejects missing domain dot and parts', () {
      expect(validateEmail(''), isNotNull);
      expect(validateEmail('not-an-email'), isNotNull);
      expect(validateEmail('user@localhost'), isNotNull);
      expect(validateEmail('user@'), isNotNull);
      expect(validateEmail('@example.com'), isNotNull);
      expect(validateEmail('a b@example.com'), isNotNull);
    });
  });

  group('validatePassword', () {
    test('rejects passwords shorter than 8 characters', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('1234567'), isNotNull);
      expect(validatePassword('Ab1!567'), isNotNull);
    });

    test('rejects single-class passwords', () {
      expect(validatePassword('abcdefgh'), isNotNull);
      expect(validatePassword('12345678'), isNotNull);
      expect(validatePassword('ABCDEFGH'), isNotNull);
    });

    test('accepts 8+ characters with at least two character classes', () {
      expect(validatePassword('brochat1'), isNull);
      expect(validatePassword('BroChat!'), isNull);
      expect(validatePassword('correct1 horse'), isNull);
    });
  });

  group('validateSignInPassword', () {
    test('rejects fewer than 6 characters and accepts 6+', () {
      expect(validateSignInPassword('12345'), isNotNull);
      expect(validateSignInPassword('123456'), isNull);
    });
  });

  group('evaluatePasswordStrength', () {
    test('classifies weak, fair, and strong passwords', () {
      expect(evaluatePasswordStrength('short'), PasswordStrength.weak);
      expect(evaluatePasswordStrength('onlyletters'), PasswordStrength.weak);
      expect(evaluatePasswordStrength('brochat1'), PasswordStrength.fair);
      expect(evaluatePasswordStrength('BroChat123'), PasswordStrength.strong);
      expect(
        evaluatePasswordStrength('Correct!Horse99'),
        PasswordStrength.strong,
      );
    });
  });

  group('loginCooldownForFailures', () {
    test('enforces progressive backoff starting at 3 failures', () {
      expect(loginCooldownForFailures(0), Duration.zero);
      expect(loginCooldownForFailures(2), Duration.zero);
      expect(loginCooldownForFailures(3), const Duration(seconds: 5));
      expect(loginCooldownForFailures(4), const Duration(seconds: 15));
      expect(loginCooldownForFailures(5), const Duration(seconds: 30));
      expect(loginCooldownForFailures(8), const Duration(seconds: 30));
    });
  });

  group('validateUsername', () {
    test('rejects short usernames', () {
      expect(validateUsername(''), isNotNull);
      expect(validateUsername('ab'), isNotNull);
    });

    test('rejects illegal characters', () {
      expect(validateUsername('bad name'), isNotNull);
      expect(validateUsername('bad!name'), isNotNull);
      expect(validateUsername('bad@name'), isNotNull);
    });

    test('accepts letters, numbers, dots, dashes and underscores', () {
      expect(validateUsername('alex_vance'), isNull);
      expect(validateUsername('alex.vance-9'), isNull);
      expect(validateUsername('ABC_123'), isNull);
    });
  });
}
