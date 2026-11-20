import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/screens/auth/login_screen.dart';

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == hint,
    );

Future<void> _pumpLogin(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
        ),
        child: const LoginScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the sign-in form by default', (tester) async {
    await _pumpLogin(tester);
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
    await _pumpLogin(tester);
    await tester.pump();

    await tester.tap(find.text('Create Account'));
    await tester.pump();

    expect(find.text('WHAT THEY CALL YOU'), findsOneWidget);
    expect(find.text('Create Account'), findsNWidgets(2)); // toggle + CTA
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('invalid email shows an inline error under the field',
      (tester) async {
    await _pumpLogin(tester);
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
    await _pumpLogin(tester);
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
    await _pumpLogin(tester);
    await tester.pump();

    await tester.enterText(_fieldWithHint('you@bro.network'), 'bro@example.com');
    await tester.enterText(_fieldWithHint('••••••••'), '123');
    await tester.tap(find.byKey(const Key('auth-cta')));
    await tester.pump();

    expect(
      find.text('Use at least 6 characters for your password.'),
      findsOneWidget,
    );
  });

  testWidgets('reduce-motion build still renders the header',
      (tester) async {
    await _pumpLogin(tester, disableAnimations: true);
    await tester.pumpAndSettle();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(find.byKey(const Key('auth-cta')), findsOneWidget);
  });
}
