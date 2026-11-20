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
    test('rejects passwords shorter than 6 characters', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword('12345'), isNotNull);
    });

    test('accepts 6 or more characters', () {
      expect(validatePassword('123456'), isNull);
      expect(validatePassword('correct horse battery staple'), isNull);
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
