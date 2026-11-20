import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/screens/auth/widgets/welcome_hero.dart';
import 'package:bro_chat/theme/app_colors.dart' as app_colors;

Finder _image(String asset) => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == asset,
      description: 'asset image $asset',
    );

Widget _host({
  bool disableAnimations = false,
  bool isSignUp = false,
  bool showFeatureCards = true,
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      backgroundColor: app_colors.P.bg,
      body: Center(
        child: SizedBox(
          width: 620,
          child: WelcomeHero(
            isSignUp: isSignUp,
            showFeatureCards: showFeatureCards,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the four regenerated hero props and the copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(find.text('All your conversations, right here.'), findsOneWidget);
    expect(find.text('BRO  ·  YOUR PEOPLE, CLOSER'), findsOneWidget);
    expect(find.text('Private by design'), findsOneWidget);
    expect(find.text('Always in sync'), findsOneWidget);

    for (final asset in const [
      HeroArt.mascot,
      HeroArt.ball,
      HeroArt.gamepad,
      HeroArt.supercar,
    ]) {
      expect(_image(asset), findsOneWidget, reason: 'missing $asset');
    }
  });

  testWidgets('sign-up variant swaps the hero copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(isSignUp: true));
    await tester.pump();

    expect(find.text('Your people.\nYour place.'), findsOneWidget);
    expect(
      find.text('Make room for the conversations that matter.'),
      findsOneWidget,
    );
  });

  testWidgets('feature cards can be switched off for short screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(showFeatureCards: false));
    await tester.pump();

    expect(find.text('Private by design'), findsNothing);
    expect(find.text('Always in sync'), findsNothing);
    expect(_image(HeroArt.mascot), findsOneWidget);
  });

  testWidgets('reduce motion settles on a static rest pose', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(disableAnimations: true));
    // If any loop kept running this would time out — the whole point of the
    // reduce-motion rest pose.
    await tester.pumpAndSettle();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(_image(HeroArt.mascot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the expressive loop keeps running without errors',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(_image(HeroArt.supercar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
