import 'dart:convert';

/// Customization for the 3D-style digital avatar shown on a user's profile.
///
/// The avatar is painted with Flutter primitives (see
/// `widgets/digital_avatar.dart`), so the whole look is described by this
/// plain data object and persisted as a `jsonb` column on `profiles`.
///
/// Unknown or malformed values are coerced back to the defaults instead of
/// throwing, so a config written by an older client can never break a profile.
class AvatarConfig {
  const AvatarConfig({
    this.enabled = false,
    this.preset = 'orb',
    this.bodyHex = '#D4FF00',
    this.expression = 'happy',
    this.accessory = 'none',
    this.auraHex = '#7C5CFF',
    this.reaction = '🔥',
    this.animationsEnabled = true,
  });

  /// Whether the digital avatar replaces the photo avatar on the profile.
  final bool enabled;

  /// Head silhouette: orb, buddy, robot or cat.
  final String preset;

  /// Body colour of the avatar.
  final String bodyHex;

  /// Facial expression: neutral, happy, wink, surprised or cool.
  final String expression;

  /// Worn accessory: none, glasses, shades, headphones, cap or halo.
  final String accessory;

  /// Glow colour behind the avatar.
  final String auraHex;

  /// Emoji used by the tap reaction effect.
  final String reaction;

  /// Idle motion (bob, breathing, blinking). Tap reactions always play.
  final bool animationsEnabled;

  static const presets = ['orb', 'buddy', 'robot', 'cat'];

  static const expressions = [
    'neutral',
    'happy',
    'wink',
    'surprised',
    'cool',
  ];

  static const accessories = [
    'none',
    'glasses',
    'shades',
    'headphones',
    'cap',
    'halo',
  ];

  static const reactions = ['🔥', '😂', '😮', '❤️', '👏', '🎉'];

  static const bodyColors = [
    '#D4FF00',
    '#7C5CFF',
    '#FF5CA8',
    '#38BDF8',
    '#FF8A3D',
    '#22C55E',
    '#F5F5F5',
    '#8B5E3C',
  ];

  static const auraColors = [
    '#7C5CFF',
    '#D4FF00',
    '#FF5CA8',
    '#38BDF8',
    '#FF8A3D',
    '#22C55E',
    '#F5F5F5',
    '#0B0C10',
  ];

  static String _choice(String value, List<String> allowed, String fallback) =>
      allowed.contains(value) ? value : fallback;

  static String _hex(String value, String fallback) =>
      RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)
          ? value.toUpperCase()
          : fallback;

  factory AvatarConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AvatarConfig();
    return AvatarConfig(
      enabled: json['enabled'] as bool? ?? false,
      preset: _choice(json['preset'] as String? ?? 'orb', presets, 'orb'),
      bodyHex:
          _hex(json['body_hex'] as String? ?? '#D4FF00', '#D4FF00'),
      expression: _choice(
          json['expression'] as String? ?? 'happy', expressions, 'happy'),
      accessory: _choice(
          json['accessory'] as String? ?? 'none', accessories, 'none'),
      auraHex:
          _hex(json['aura_hex'] as String? ?? '#7C5CFF', '#7C5CFF'),
      reaction: _choice(json['reaction'] as String? ?? '🔥', reactions, '🔥'),
      animationsEnabled: json['animations_enabled'] as bool? ?? true,
    );
  }

  /// Reads a `jsonb` value as returned by PostgREST, which may already be a
  /// decoded map or still be a JSON string depending on the transport.
  static AvatarConfig fromStorage(dynamic raw) {
    if (raw == null) return const AvatarConfig();
    if (raw is AvatarConfig) return raw;
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const AvatarConfig();
      try {
        return AvatarConfig.fromJson(
            jsonDecode(trimmed) as Map<String, dynamic>);
      } catch (_) {
        return const AvatarConfig();
      }
    }
    if (raw is Map) {
      return AvatarConfig.fromJson(Map<String, dynamic>.from(raw));
    }
    return const AvatarConfig();
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preset': preset,
        'body_hex': bodyHex,
        'expression': expression,
        'accessory': accessory,
        'aura_hex': auraHex,
        'reaction': reaction,
        'animations_enabled': animationsEnabled,
      };

  AvatarConfig copyWith({
    bool? enabled,
    String? preset,
    String? bodyHex,
    String? expression,
    String? accessory,
    String? auraHex,
    String? reaction,
    bool? animationsEnabled,
  }) =>
      AvatarConfig(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        bodyHex: bodyHex ?? this.bodyHex,
        expression: expression ?? this.expression,
        accessory: accessory ?? this.accessory,
        auraHex: auraHex ?? this.auraHex,
        reaction: reaction ?? this.reaction,
        animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      );

  @override
  bool operator ==(Object other) =>
      other is AvatarConfig &&
      other.enabled == enabled &&
      other.preset == preset &&
      other.bodyHex == bodyHex &&
      other.expression == expression &&
      other.accessory == accessory &&
      other.auraHex == auraHex &&
      other.reaction == reaction &&
      other.animationsEnabled == animationsEnabled;

  @override
  int get hashCode =>
      Object.hash(enabled, preset, bodyHex, expression, accessory, auraHex,
          reaction, animationsEnabled);

  @override
  String toString() =>
      'AvatarConfig($preset, $expression, $accessory, $bodyHex, $auraHex, '
      '$reaction, enabled: $enabled)';
}
