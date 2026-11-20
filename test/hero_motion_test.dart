import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/ui/hero_motion.dart';

void main() {
  group('HeroOrbitPose', () {
    test('phase 0 sits on the right of the ellipse, mid depth', () {
      final pose = HeroOrbitPose.at(phase: 0, radiusX: 100, radiusY: 40);

      expect(pose.offset.dx, closeTo(100, 0.001));
      expect(pose.offset.dy, closeTo(0, 0.001));
      expect(pose.depth, closeTo(0, 0.001));
      // minScale 0.84 .. maxScale 1.06 -> midpoint 0.95
      expect(pose.scale, closeTo(0.95, 0.001));
      expect(pose.isBehind, isFalse);
    });

    test('a quarter loop is the near side, half a loop the far side', () {
      final near = HeroOrbitPose.at(phase: 0.25, radiusX: 100, radiusY: 40);
      expect(near.depth, closeTo(1, 0.001));
      expect(near.scale, closeTo(1.06, 0.001));
      expect(near.offset.dy, closeTo(40, 0.001));
      expect(near.isBehind, isFalse);

      final far = HeroOrbitPose.at(phase: 0.75, radiusX: 100, radiusY: 40);
      expect(far.depth, closeTo(-1, 0.001));
      expect(far.scale, closeTo(0.84, 0.001));
      expect(far.offset.dy, closeTo(-40, 0.001));
      expect(far.isBehind, isTrue);
    });

    test('angleOffset staggers props around the same path', () {
      final lead = HeroOrbitPose.at(phase: 0);
      final staggered = HeroOrbitPose.at(phase: 0, angleOffset: 1.5707963267948966);

      expect(staggered.offset.dx, closeTo(lead.offset.dy, 0.001));
      expect(staggered.depth, closeTo(1, 0.001));
    });

    test('turns changes how fast a prop laps the loop', () {
      final halfSpeed = HeroOrbitPose.at(phase: 0.5, turns: 0.5);
      expect(halfSpeed.depth, closeTo(1, 0.001));
    });

    test('sortKey orders far props before near props', () {
      final far = HeroOrbitPose.at(phase: 0.75);
      final near = HeroOrbitPose.at(phase: 0.25);
      expect(far.sortKey, lessThan(near.sortKey));
    });

    test('poses are pure functions of the phase', () {
      final a = HeroOrbitPose.at(phase: 0.37, angleOffset: 1.2, turns: 0.9);
      final b = HeroOrbitPose.at(phase: 0.37, angleOffset: 1.2, turns: 0.9);
      expect(a.offset, b.offset);
      expect(a.depth, b.depth);
      expect(a.scale, b.scale);
      expect(a.yaw, b.yaw);
      expect(a.roll, b.roll);
    });
  });

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

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(400, 400)));
      await tester.pumpAndSettle();

      expect(latest.dx, greaterThan(0.9));
      expect(latest.dy, greaterThan(0.9));
    });

    testWidgets('reduce-motion never listens to the pointer', (tester) async {
      Offset latest = const Offset(1, 1);
      await tester.pumpWidget(
        harness(enabled: false, onShift: (s) => latest = s),
      );

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(400, 400)));
      await tester.pumpAndSettle();

      expect(latest, Offset.zero);
    });
  });
}
