import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/screens/auth/login_screen.dart';

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == hint,
    );

Widget _app({
  bool disableAnimations = false,
  Future<void> Function(String email, String password)? onSignIn,
  Future<bool> Function(String password)? onLeakedCheck,
}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: LoginScreen(
        onSignIn: onSignIn,
        onLeakedCheck: onLeakedCheck,
      ),
    );

void main() {
  testWidgets('renders the sign-in form by default', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('WHAT THEY CALL YOU'), findsNothing);
    expect(find.byKey(const Key('auth-cta')), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('create-account toggle reveals the username field',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(find.text('WHAT THEY CALL YOU'), findsOneWidget);
    // Toggle + CTA both read "Create Account" now.
    expect(find.text('Create Account'), findsNWidgets(2));
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('invalid email shows an inline error under the field',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.enterText(_fieldWithHint('you@bro.network'), 'not-an-email');
    await tester.tap(find.byKey(const Key('auth-cta')));
    await tester.pump();

    expect(
      find.text("That email doesn't look quite right."),
      findsOneWidget,
    );
  });

  testWidgets('forgot password requires a valid email first',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.enterText(_fieldWithHint('you@bro.network'), 'nope');
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();

    expect(
      find.text("That email doesn't look quite right."),
      findsOneWidget,
    );
  });

  testWidgets('short password shows an inline error', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester
        .enterText(_fieldWithHint('you@bro.network'), 'bro@example.com');
    await tester.enterText(_fieldWithHint('••••••••'), '123');
    await tester.tap(find.byKey(const Key('auth-cta')));
    await tester.pump();

    expect(
      find.text('Use at least 6 characters for your password.'),
      findsOneWidget,
    );
  });

  testWidgets('reduce-motion build disables the hero loop',
      (tester) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    await tester.pumpAndSettle();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(find.byKey(const Key('auth-cta')), findsOneWidget);
  });

  testWidgets('sign-up mode shows live password strength meter',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.text('Create Account'));
    await tester.pump();

    await tester.enterText(_fieldWithHint('••••••••'), 'abc');
    await tester.pump();
    expect(find.text('Weak'), findsOneWidget);

    await tester.enterText(_fieldWithHint('••••••••'), 'brochat1');
    await tester.pump();
    expect(find.text('Fair'), findsOneWidget);

    await tester.enterText(_fieldWithHint('••••••••'), 'BroChat!2026');
    await tester.pump();
    expect(find.text('Strong'), findsOneWidget);
  });

  testWidgets('sign-in enforces cooldown after 3 consecutive failures',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(_app(
      onSignIn: (_, __) async {
        attempts += 1;
        throw StateError('Invalid credentials');
      },
    ));
    await tester.pump();

    await tester
        .enterText(_fieldWithHint('you@bro.network'), 'bro@example.com');
    await tester.enterText(_fieldWithHint('••••••••'), 'wrongpass1');

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('auth-cta')));
      await tester.pump();
    }

    expect(attempts, 3);
    expect(find.text('Too many attempts. Try again in 5s.'), findsOneWidget);
    expect(find.text('Wait 5s'), findsOneWidget);

    // Advance past the 5-second cooldown so no pending timer remains.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Sign In'), findsWidgets);
  });

  testWidgets('renders Google and GitHub OAuth buttons', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Google'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
  });
}
