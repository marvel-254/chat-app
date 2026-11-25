import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/screens/auth/login_screen.dart';
import 'package:bro_chat/screens/navigation/nav_sidebar.dart';
import 'package:bro_chat/services/supabase.dart';
import 'package:bro_chat/theme/app_colors.dart' as app_colors;
import 'package:bro_chat/widgets/home_nav_bar.dart';
import 'package:bro_chat/widgets/responsive_app_shell.dart';

Widget _shellApp({
  required Size size,
  Widget? leading,
}) {
  final router = GoRouter(
    initialLocation: '/conversations',
    routes: [
      GoRoute(
        path: '/conversations',
        builder: (_, __) => ResponsiveAppShell(
          title: 'Chats',
          subtitle: 'Your conversations',
          navIndex: 0,
          leading: leading,
          body: const Center(child: Text('shell-body')),
        ),
      ),
      GoRoute(
        path: '/circles',
        builder: (_, __) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/recent-calls',
        builder: (_, __) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/status',
        builder: (_, __) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SizedBox.shrink(),
      ),
    ],
  );
  return MediaQuery(
    data: MediaQueryData(size: size, disableAnimations: true),
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  test('screenSizeClassForWidth classifies Android, tablet, and desktop', () {
    expect(
      app_colors.screenSizeClassForWidth(390),
      app_colors.ScreenSizeClass.compact,
    );
    expect(
      app_colors.screenSizeClassForWidth(599),
      app_colors.ScreenSizeClass.compact,
    );
    expect(
      app_colors.screenSizeClassForWidth(600),
      app_colors.ScreenSizeClass.tablet,
    );
    expect(
      app_colors.screenSizeClassForWidth(768),
      app_colors.ScreenSizeClass.tablet,
    );
    expect(
      app_colors.screenSizeClassForWidth(959),
      app_colors.ScreenSizeClass.tablet,
    );
    expect(
      app_colors.screenSizeClassForWidth(960),
      app_colors.ScreenSizeClass.desktop,
    );
    expect(
      app_colors.screenSizeClassForWidth(1440),
      app_colors.ScreenSizeClass.desktop,
    );
  });

  testWidgets('Android viewport uses bottom HomeNavBar and AppBar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_shellApp(size: const Size(390, 844)));
    await tester.pumpAndSettle();

    expect(find.byType(HomeNavBar), findsOneWidget);
    expect(find.byType(NavSidebar), findsNothing);
    expect(find.text('shell-body'), findsOneWidget);
  });

  testWidgets('Tablet viewport uses compact 76px NavSidebar and keeps leading',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(768, 1024));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _shellApp(
        size: const Size(768, 1024),
        leading: const Icon(Icons.arrow_back, key: Key('header-back')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeNavBar), findsNothing);
    final sidebar = tester.widget<NavSidebar>(find.byType(NavSidebar));
    expect(sidebar.compact, isTrue);
    expect(tester.getSize(find.byType(NavSidebar)).width, 76.0);
    expect(find.byKey(const Key('header-back')), findsOneWidget);
  });

  testWidgets('Desktop viewport uses full 240px NavSidebar and keeps leading',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _shellApp(
        size: const Size(1280, 800),
        leading: const Icon(Icons.arrow_back, key: Key('header-back')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HomeNavBar), findsNothing);
    final sidebar = tester.widget<NavSidebar>(find.byType(NavSidebar));
    expect(sidebar.compact, isFalse);
    expect(tester.getSize(find.byType(NavSidebar)).width, 240.0);
    expect(find.byKey(const Key('header-back')), findsOneWidget);
  });

  for (final entry in {
    'Android': const Size(390, 844),
    'Tablet': const Size(768, 1024),
    'Desktop': const Size(1280, 800),
  }.entries) {
    testWidgets('LoginScreen fits ${entry.key} (${entry.value}) cleanly',
        (tester) async {
      await tester.binding.setSurfaceSize(entry.value);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: entry.value, disableAnimations: true),
          child: const MaterialApp(home: LoginScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Good to see you, Bro.'), findsOneWidget);
      expect(find.byKey(const Key('auth-cta')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('sortConversationsByRecent moves newest messages to the top', () {
    final base = DateTime.utc(2026, 11, 25, 10, 0);
    final older = Conversation(
      id: 'c-old',
      createdAt: base,
      updatedAt: base,
      lastMessageAt: base.add(const Duration(minutes: 5)),
    );
    final newer = Conversation(
      id: 'c-new',
      createdAt: base.subtract(const Duration(days: 1)),
      updatedAt: base,
      lastMessageAt: base.add(const Duration(minutes: 30)),
    );
    final noMessageYet = Conversation(
      id: 'c-fresh',
      createdAt: base,
      updatedAt: base.add(const Duration(minutes: 15)),
    );

    final sorted =
        Supa.sortConversationsByRecent([older, noMessageYet, newer]);
    expect(sorted.map((c) => c.id).toList(), ['c-new', 'c-fresh', 'c-old']);
  });
}
