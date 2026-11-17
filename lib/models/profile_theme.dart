/// Custom presentation settings shown on a user's profile.
class ProfileTheme {
  const ProfileTheme({
    this.colorHex = '#D4FF00',
    this.coverImagePath,
    this.musicPath,
    this.musicName,
    this.animatedAvatarEnabled = false,
    this.animatedAvatarPath,
    this.statusMessage,
  });

  final String colorHex;
  final String? coverImagePath;
  final String? musicPath;
  final String? musicName;
  final bool animatedAvatarEnabled;
  final String? animatedAvatarPath;
  final String? statusMessage;

  factory ProfileTheme.fromJson(Map<String, dynamic> json) => ProfileTheme(
        colorHex: json['profile_color'] as String? ?? '#D4FF00',
        coverImagePath: json['cover_image_path'] as String?,
        musicPath: json['profile_music_path'] as String?,
        musicName: json['profile_music_name'] as String?,
        animatedAvatarEnabled:
            json['animated_avatar_enabled'] as bool? ?? false,
        animatedAvatarPath: json['animated_avatar_path'] as String?,
        statusMessage: json['profile_status'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'profile_color': colorHex,
        'cover_image_path': coverImagePath,
        'profile_music_path': musicPath,
        'profile_music_name': musicName,
        'animated_avatar_enabled': animatedAvatarEnabled,
        'animated_avatar_path': animatedAvatarPath,
        'profile_status': statusMessage,
      };
}
