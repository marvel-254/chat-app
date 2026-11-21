import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/ui/hero_motion.dart';

void main() {
  group('HeroEntrance', () {
    testWidgets('rest pose shows the child fully', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HeroEntrance(
            animation: const AlwaysStoppedAnimation<double>(1.0),
            index: 3,
            child: const Text('settled'),
          ),
        ),
      );

      expect(find.text('settled'), findsOneWidget);
      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(HeroEntrance),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1);
    });

    testWidgets('starts hidden when the intro has not run', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HeroEntrance(
            animation: const AlwaysStoppedAnimation<double>(0.0),
            index: 0,
            child: const Text('hidden'),
          ),
        ),
      );

      final fade = tester.widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(HeroEntrance),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 0);
    });
  });

  group('HeroParallax', () {
    Widget harness({required bool enabled, required void Function(Offset) onShift}) {
      return MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 400,
            child: HeroParallax(
              enabled: enabled,
              builder: (context, shift) {
                onShift(shift);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
    }

    testWidgets('reports a normalised shift while the pointer hovers',
        (tester) async {
      Offset latest = Offset.zero;
      await tester.pumpWidget(harness(enabled: true, onShift: (s) => latest = s));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(200, 200));
      addTearDown(gesture.removePointer);
      await tester.pump();
      // Stay a hair inside the box: the bottom/right edges are exclusive.
      await gesture.moveTo(const Offset(396, 396));
      await tester.pumpAndSettle();

      expect(latest.dx, greaterThan(0.9));
      expect(latest.dy, greaterThan(0.9));
    });

    testWidgets('reduce-motion never listens to the pointer', (tester) async {
      Offset latest = const Offset(1, 1);
      await tester.pumpWidget(
        harness(enabled: false, onShift: (s) => latest = s),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(200, 200));
      addTearDown(gesture.removePointer);
      await tester.pump();
      await gesture.moveTo(const Offset(396, 396));
      await tester.pumpAndSettle();

      expect(latest, Offset.zero);
    });
  });
}
