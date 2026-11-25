import 'package:bro_chat/screens/auth/mfa_challenge_screen.dart';
import 'package:bro_chat/screens/auth/reset_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );

void main() {
  group('ResetPasswordScreen', () {
    testWidgets('rejects weak/mismatched passwords and blocks leaked passwords',
        (tester) async {
      var updated = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ResetPasswordScreen(
            onLeakedCheck: (pwd) async => pwd == 'Password123',
            onUpdatePassword: (_) async {
              updated = true;
            },
          ),
        ),
      );

      final fields = _fieldWithHint('••••••••');
      await tester.enterText(fields.at(0), 'Password123');
      await tester.enterText(fields.at(1), 'Password123');
      await tester.tap(find.byKey(const Key('reset-password-cta')));
      await tester.pump();

      expect(
        find.text(
          'This password has appeared in a known data breach. Please choose a different one.',
        ),
        findsOneWidget,
      );
      expect(updated, isFalse);
    });

    testWidgets('updates password when strong and not leaked', (tester) async {
      String? capturedPassword;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ResetPasswordScreen(
            onLeakedCheck: (_) async => false,
            onUpdatePassword: (pwd) async {
              capturedPassword = pwd;
            },
            onComplete: () {
              completed = true;
            },
          ),
        ),
      );

      final fields = _fieldWithHint('••••••••');
      await tester.enterText(fields.at(0), 'UniqueBro!2026');
      await tester.enterText(fields.at(1), 'UniqueBro!2026');
      await tester.tap(find.byKey(const Key('reset-password-cta')));
      await tester.pump();

      expect(capturedPassword, 'UniqueBro!2026');
      expect(completed, isTrue);
    });
  });

  group('MfaChallengeScreen', () {
    testWidgets('requires 6 digits and invokes verification callback',
        (tester) async {
      String? verifiedCode;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MfaChallengeScreen(
            onVerifyCode: (code) async {
              verifiedCode = code;
            },
            onVerified: () {
              done = true;
            },
          ),
        ),
      );

      await tester.enterText(_fieldWithHint('123456'), '12');
      await tester.tap(find.byKey(const Key('mfa-verify-cta')));
      await tester.pump();
      expect(
        find.text('Enter the 6-digit code from your app.'),
        findsOneWidget,
      );
      expect(done, isFalse);

      await tester.enterText(_fieldWithHint('123456'), '654321');
      await tester.tap(find.byKey(const Key('mfa-verify-cta')));
      await tester.pump();
      expect(verifiedCode, '654321');
      expect(done, isTrue);
    });
  });
}
