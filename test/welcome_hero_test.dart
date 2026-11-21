import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/screens/auth/widgets/auth_prop.dart';
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
          child: WelcomeHero(isSignUp: isSignUp),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the login hero is one prop plus the welcome copy',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(find.text('All your conversations, right here.'), findsOneWidget);
    expect(find.text('BRO  ·  YOUR PEOPLE, CLOSER'), findsOneWidget);

    // Exactly one prop, and only the mascot.
    expect(find.byType(AuthProp), findsOneWidget);
    expect(_image(AuthArt.mascot), findsOneWidget);
    expect(_image(AuthArt.chat), findsNothing);
    expect(_image(AuthArt.circle), findsNothing);
    expect(_image(AuthArt.bolt), findsNothing);
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
    expect(_image(AuthArt.mascot), findsOneWidget);
  });

  testWidgets('reduce motion settles on a still prop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host(disableAnimations: true));
    // If the idle float kept running this would time out.
    await tester.pumpAndSettle();

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(_image(AuthArt.mascot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the idle float runs without errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(_image(AuthArt.mascot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
