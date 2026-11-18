import 'profile.dart';

/// Gaming platforms a BRO profile can link.
///
/// Values must stay in sync with the `profiles_game_platform_check`
/// constraint in supabase/migrations/20261118010000_gaming_profiles.sql.
const List<({String value, String label})> gamePlatforms = [
  (value: 'steam', label: 'Steam'),
  (value: 'xbox', label: 'Xbox'),
  (value: 'playstation', label: 'PlayStation'),
  (value: 'nintendo', label: 'Nintendo'),
  (value: 'battle_net', label: 'Battle.net'),
  (value: 'epic', label: 'Epic Games'),
  (value: 'riot', label: 'Riot Games'),
  (value: 'ubisoft', label: 'Ubisoft'),
  (value: 'ea', label: 'EA'),
  (value: 'gog', label: 'GOG'),
  (value: 'custom', label: 'Other'),
];

const int gameUsernameMaxLength = 50;
const int gameStatusMaxLength = 100;

/// Games offered as one-tap suggestions in the gaming profile editor.
const List<String> suggestedGames = [
  'Valorant',
  'EA FC 26',
  'Fortnite',
  'Minecraft',
  'GTA V',
  'Call of Duty',
  'Apex Legends',
  'Rocket League',
  'League of Legends',
  'Counter-Strike 2',
];

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Human label for a stored platform value, or null when it is unset/unknown.
String? gamePlatformLabel(String? platform) {
  final key = _clean(platform);
  if (key == null) return null;
  for (final entry in gamePlatforms) {
    if (entry.value == key) return entry.label;
  }
  return null;
}

/// Validation for the gaming profile editor. Returns a message, or null when
/// the values can be saved. Mirrors the database check constraints.
String? gameProfileError({
  String? platform,
  String? username,
  String? status,
}) {
  final p = _clean(platform);
  final u = _clean(username);
  final s = _clean(status);
  if (u != null && u.length > gameUsernameMaxLength) {
    return 'Your game username must be $gameUsernameMaxLength characters or fewer.';
  }
  if (s != null && s.length > gameStatusMaxLength) {
    return 'The game you are playing must be $gameStatusMaxLength characters or fewer.';
  }
  if (p != null && u == null) {
    final label = gamePlatformLabel(p) ?? 'that platform';
    return 'Add your game username so friends can find you on $label.';
  }
  return null;
}

/// The gaming slice of a profile: handle, platform, and current game.
///
/// Every field is masked together by `visible_profiles`, so a visible
/// presence always carries a handle.
class GamePresence {
  const GamePresence({this.platform, this.username, this.status});

  factory GamePresence.fromProfile(Profile profile) => GamePresence(
        platform: profile.gamePlatform,
        username: profile.gameUsername,
        status: profile.gameStatus,
      );

  final String? platform;
  final String? username;
  final String? status;

  String? get _handle => _clean(username);
  String? get _game => _clean(status);

  /// Whether there is anything to show to this viewer.
  bool get isVisible => _handle != null;

  String? get platformLabel => gamePlatformLabel(platform);

  /// "Playing Valorant" — the line shown under a friend's name.
  String? get playingLabel {
    final game = _game;
    if (game == null) return null;
    if (game.toLowerCase().startsWith('playing')) return game;
    return 'Playing $game';
  }

  /// "Steam · @handle" — the handle line on a profile card.
  String? get handleLabel {
    final handle = _handle;
    if (handle == null) return null;
    final label = platformLabel;
    return label == null ? '@$handle' : '$label · @$handle';
  }
}
