import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/models/avatar_config.dart';
import 'package:bro_chat/widgets/digital_avatar.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('AvatarConfig', () {
    test('falls back to defaults for null or empty json', () {
      const expected = AvatarConfig();
      expect(AvatarConfig.fromJson(null), expected);
      expect(AvatarConfig.fromJson(const {}), expected);
      expect(AvatarConfig.fromStorage(null), expected);
      expect(AvatarConfig.fromStorage(''), expected);
      expect(AvatarConfig.fromStorage('not json'), expected);
    });

    test('round-trips through json', () {
      const config = AvatarConfig(
        enabled: true,
        preset: 'robot',
        bodyHex: '#38BDF8',
        expression: 'wink',
        accessory: 'headphones',
        auraHex: '#FF5CA8',
        reaction: '🎉',
        animationsEnabled: false,
      );
      final restored = AvatarConfig.fromJson(config.toJson());
      expect(restored, config);
      expect(restored.hashCode, config.hashCode);
    });

    test('coerces unknown enum values back to defaults', () {
      final config = AvatarConfig.fromJson({
        'preset': 'spaceship',
        'expression': 'sleepy',
        'accessory': 'crown',
        'reaction': '🤖',
      });
      expect(config.preset, 'orb');
      expect(config.expression, 'happy');
      expect(config.accessory, 'none');
      expect(config.reaction, '🔥');
    });

    test('rejects malformed hex colours', () {
      final config = AvatarConfig.fromJson({
        'body_hex': 'red',
        'aura_hex': '#12345',
      });
      expect(config.bodyHex, '#D4FF00');
      expect(config.auraHex, '#7C5CFF');
    });

    test('normalises valid hex colours to upper case', () {
      final config = AvatarConfig.fromJson({
        'body_hex': '#d4ff00',
      });
      expect(config.bodyHex, '#D4FF00');
    });

    test('reads a json string as returned by some transports', () {
      final config = AvatarConfig.fromStorage(jsonEncode({
        'preset': 'cat',
        'enabled': true,
      }));
      expect(config.preset, 'cat');
      expect(config.enabled, isTrue);
    });

    test('copyWith only changes the supplied fields', () {
      const base = AvatarConfig();
      final next = base.copyWith(expression: 'cool', accessory: 'halo');
      expect(next.expression, 'cool');
      expect(next.accessory, 'halo');
      expect(next.preset, base.preset);
      expect(next.bodyHex, base.bodyHex);
      expect(next.enabled, base.enabled);
    });
  });

  group('DigitalAvatar', () {
    testWidgets('renders a custom-painted avatar', (tester) async {
      await tester.pumpWidget(_host(const DigitalAvatar(
        config: AvatarConfig(animationsEnabled: false),
        size: 96,
      )));
      expect(tester.takeException(), isNull);
      expect(find.byType(DigitalAvatar), findsOneWidget);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('plays the reaction effect when tapped', (tester) async {
      var reactions = 0;
      await tester.pumpWidget(_host(DigitalAvatar(
        config: const AvatarConfig(animationsEnabled: false),
        size: 96,
        onReact: () => reactions++,
      )));

      await tester.tap(find.byType(DigitalAvatar));
      await tester.pump();
      expect(reactions, 1);

      // Let the 900ms reaction animation finish.
      await tester.pump(const Duration(milliseconds: 950));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ignores taps when interactive is false', (tester) async {
      var reactions = 0;
      await tester.pumpWidget(_host(DigitalAvatar(
        config: const AvatarConfig(animationsEnabled: false),
        size: 96,
        interactive: false,
        onReact: () => reactions++,
      )));

      await tester.tap(find.byType(DigitalAvatar));
      await tester.pump();
      expect(reactions, 0);
    });

    testWidgets('repaints when the config changes', (tester) async {
      await tester.pumpWidget(_host(const DigitalAvatar(
        config: AvatarConfig(animationsEnabled: false),
        size: 96,
      )));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_host(const DigitalAvatar(
        config: AvatarConfig(
          animationsEnabled: false,
          preset: 'cat',
          expression: 'surprised',
          accessory: 'cap',
        ),
        size: 96,
      )));
      expect(tester.takeException(), isNull);
    });
  });
}
