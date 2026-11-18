import 'package:bro_chat/models/game_profile.dart';
import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/widgets/game_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _profile({
  String? platform,
  String? username,
  String? status,
  String visibility = 'everyone',
}) =>
    Profile(
      id: 'user-1',
      username: 'gamer',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      photoVisibility: 'everyone',
      statusVisibility: 'everyone',
      aboutVisibility: 'everyone',
      readReceiptsEnabled: true,
      gamePlatform: platform,
      gameUsername: username,
      gameStatus: status,
      gameVisibility: visibility,
    );

void main() {
  test('Profile parses gaming fields with defaults', () {
    final bare = Profile.fromJson({
      'id': 'user-1',
      'username': 'gamer',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    expect(bare.gamePlatform, isNull);
    expect(bare.gameUsername, isNull);
    expect(bare.gameStatus, isNull);
    expect(bare.gameVisibility, 'everyone');

    final full = Profile.fromJson({
      'id': 'user-2',
      'username': 'gamer',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'game_platform': 'steam',
      'game_username': 'gearlord',
      'game_status': 'Counter-Strike 2',
      'game_visibility': 'contacts',
    });
    expect(full.gamePlatform, 'steam');
    expect(full.gameUsername, 'gearlord');
    expect(full.gameStatus, 'Counter-Strike 2');
    expect(full.gameVisibility, 'contacts');
  });

  test('playingLabel prefixes the game being played', () {
    expect(
      GamePresence.fromProfile(
        _profile(platform: 'steam', username: 'gearlord', status: 'Valorant'),
      ).playingLabel,
      'Playing Valorant',
    );
  });

  test('playingLabel keeps an explicit playing prefix', () {
    expect(
      const GamePresence(status: 'Playing Valorant').playingLabel,
      'Playing Valorant',
    );
    expect(
      const GamePresence(status: 'playing ranked').playingLabel,
      'playing ranked',
    );
  });

  test('presence is hidden without a handle', () {
    expect(const GamePresence(status: 'Valorant').isVisible, isFalse);
    expect(const GamePresence().playingLabel, isNull);
    expect(
      const GamePresence(platform: 'steam', username: '  ').handleLabel,
      isNull,
    );
  });

  test('platform labels come from the stored value', () {
    expect(gamePlatformLabel('steam'), 'Steam');
    expect(gamePlatformLabel('battle_net'), 'Battle.net');
    expect(gamePlatformLabel('custom'), 'Other');
    expect(gamePlatformLabel(' playstation '), 'PlayStation');
    expect(gamePlatformLabel('nintendo-switch'), isNull);
    expect(gamePlatformLabel(null), isNull);
  });

  test('handleLabel joins platform and handle', () {
    expect(
      const GamePresence(platform: 'xbox', username: 'nxgamer').handleLabel,
      'Xbox · @nxgamer',
    );
    expect(const GamePresence(username: 'nxgamer').handleLabel, '@nxgamer');
  });

  test('gameProfileError mirrors the database constraints', () {
    expect(
      gameProfileError(platform: 'steam', username: 'gearlord', status: 'A'),
      isNull,
    );
    expect(gameProfileError(), isNull);
    expect(
      gameProfileError(platform: 'steam', username: '   '),
      contains('game username'),
    );
    expect(
      gameProfileError(username: 'a' * gameUsernameMaxLength),
      isNull,
    );
    expect(
      gameProfileError(username: 'a' * (gameUsernameMaxLength + 1)),
      contains('50 characters'),
    );
    expect(
      gameProfileError(status: 'g' * (gameStatusMaxLength + 1)),
      contains('100 characters'),
    );
  });

  test('suggested games fit the status limit', () {
    for (final game in suggestedGames) {
      expect(game.length, lessThanOrEqualTo(gameStatusMaxLength));
    }
    expect(suggestedGames, isNotEmpty);
  });

  testWidgets('GamePresenceTag renders the label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GamePresenceTag(label: 'Playing Valorant')),
      ),
    );
    expect(find.text('Playing Valorant'), findsOneWidget);
    expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
  });
}
