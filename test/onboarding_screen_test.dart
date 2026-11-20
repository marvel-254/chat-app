import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bro_chat/screens/auth/onboarding_screen.dart';

Widget _buildApp({bool disableAnimations = true}) {
  final router = GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('login-destination')),
        ),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      );
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('walks through all three pages to get started',
      (tester) async {
    await tester.pumpWidget(_buildApp(disableAnimations: true));
    await tester.pumpAndSettle();

    expect(find.text('For the people\nwho feel like home.'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your circle.\nYour rules.'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Fast. Personal.\nYours.'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('login-destination'), findsOneWidget);
    expect(onboardingCompleted, isTrue);
  });

  testWidgets('skip jumps straight to the login route', (tester) async {
    await tester.pumpWidget(_buildApp(disableAnimations: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('login-destination'), findsOneWidget);
  });

  testWidgets('page dots expose labeled, tappable semantics',
      (tester) async {
    await tester.pumpWidget(_buildApp(disableAnimations: true));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Go to page 1 of 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Go to page 3 of 3'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Go to page 3 of 3'));
    await tester.pumpAndSettle();

    expect(find.text('Fast. Personal.\nYours.'), findsOneWidget);
  });

  testWidgets('first-run route renders before animation completes',
      (tester) async {
    await tester.pumpWidget(_buildApp(disableAnimations: false));
    await tester.pump();

    expect(find.text('For the people\nwho feel like home.'), findsOneWidget);

    // Let the staggered entrance finish so no timers are left pending.
    await tester.pump(const Duration(seconds: 2));
  });
}
