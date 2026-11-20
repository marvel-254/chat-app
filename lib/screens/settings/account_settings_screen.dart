import '../../services/push_notifications.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/avatar_upload.dart';
import '../../models/profile.dart';
import '../../models/profile_theme.dart';
import '../../models/game_profile.dart';
import '../../ui/states.dart';
import '../../ui/errors.dart';
import '../lock_gate.dart';
import '../../services/presence.dart';
import '../../followers_following_screen.dart';
import '../../app_constants.dart';
import '../../services/app_lock.dart';
import '../../models/avatar_config.dart';
import '../../widgets/digital_avatar.dart';
import '../chat/widgets/avatar.dart';
import '../../widgets/responsive_app_shell.dart';

const _chatBackgroundOptions = app_colors.chatBackgroundOptions;

class _P {
  static const bg = app_colors.bg;
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const success = app_colors.success;
  static const primary = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
}

Color _profileThemeColor(ProfileTheme theme) {
  final value = theme.colorHex;
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) return _P.primary;
  return Color(int.parse('FF${value.substring(1)}', radix: 16));
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _about = TextEditingController();
  final _profileStatus = TextEditingController();
  final _profileColor = TextEditingController(text: '#D4FF00');
  final _gameUsername = TextEditingController();
  final _gameStatus = TextEditingController();
  Profile? _profile;
  Uint8List? _avatarPreview;
  String? _avatarUrlOverride;
  bool _uploadingAvatar = false;
  String _chatBackground = 'default';
  String? _chatBackgroundImagePath;
  String? _chatBackgroundImageUrl;
  String? _coverImagePath;
  String? _coverImageUrl;
  String? _profileMusicPath;
  String? _profileMusicName;
  bool _animatedAvatarEnabled = false;
  String? _animatedAvatarPath;
  AvatarConfig? _digitalAvatar;
  bool _uploadingProfileMedia = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _photoVisibility = 'everyone';
  String _statusVisibility = 'everyone';
  String _aboutVisibility = 'everyone';
  bool _readReceiptsEnabled = true;
  Duration? _defaultMessageExpiry;
  Duration? _autoLockTimer;
  String? _gamePlatform;
  String _gameVisibility = 'everyone';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await Supa.getProfile(Supa.currentUser!.id);
      if (!mounted) return;
      _profile = profile;
      _username.text = profile?.username ?? '';
      _displayName.text = profile?.displayName ?? '';
      _about.text = profile?.about ?? '';
      _profileStatus.text = profile?.theme.statusMessage ?? '';
      _profileColor.text = profile?.theme.colorHex ?? '#D4FF00';
      _coverImagePath = profile?.theme.coverImagePath;
      _profileMusicPath = profile?.theme.musicPath;
      _profileMusicName = profile?.theme.musicName;
      _animatedAvatarEnabled = profile?.theme.animatedAvatarEnabled ?? false;
      _animatedAvatarPath = profile?.theme.animatedAvatarPath;
      _coverImageUrl = _coverImagePath == null
          ? null
          : Supa.profileMediaUrl(_coverImagePath!);
      _photoVisibility = profile?.photoVisibility ?? 'everyone';
      _statusVisibility = profile?.statusVisibility ?? 'everyone';
      _aboutVisibility = profile?.aboutVisibility ?? 'everyone';
      _readReceiptsEnabled = profile?.readReceiptsEnabled ?? true;
      _defaultMessageExpiry = profile?.defaultMessageExpiry;
      _autoLockTimer = profile?.autoLockTimer;
      _gamePlatform = profile?.gamePlatform;
      _gameUsername.text = profile?.gameUsername ?? '';
      _gameStatus.text = profile?.gameStatus ?? '';
      _gameVisibility = profile?.gameVisibility ?? 'everyone';
      _chatBackground = profile?.chatBackground ?? 'default';
      _chatBackgroundImagePath = profile?.chatBackgroundImagePath;
      if (_chatBackgroundImagePath != null) {
        _chatBackgroundImageUrl =
            await Supa.chatBackgroundUrl(_chatBackgroundImagePath!);
      }
      final avatarUid = profile?.id ?? Supa.currentUser?.id;
      if (avatarUid != null) {
        try {
          _digitalAvatar = await Supa.getDigitalAvatarConfig(avatarUid);
        } catch (_) {
          _digitalAvatar = null;
        }
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "We couldn't load your settings right now.";
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar || _saving) return;
    final owner = Supa.currentUser?.id;
    if (owner == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
      if (file == null || !mounted || Supa.currentUser?.id != owner) return;
      final bytes = await file.readAsBytes();
      if (!mounted || Supa.currentUser?.id != owner) return;
      avatarFormat(bytes);
      setState(() => _avatarPreview = bytes);
      final url = await Supa.uploadAvatar(bytes);
      if (!mounted || Supa.currentUser?.id != owner) return;
      setState(() => _avatarUrlOverride = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated.')),
      );
    } catch (error) {
      if (!mounted || Supa.currentUser?.id != owner) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyErrorMessage(error,
            fallback:
                "We couldn't update your photo. Try a JPEG, PNG, WebP, or GIF under 5 MB.")),
      ));
    } finally {
      if (mounted) {
        setState(() {
          _avatarPreview = null;
          _uploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _pickChatBackground() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (file == null) return;
      final path =
          await Supa.uploadChatBackground(await file.readAsBytes(), file.name);
      final url = await Supa.chatBackgroundUrl(path);
      await Supa.updateChatBackground('custom', imagePath: path);
      Supa.notifyChatBackgroundChanged();
      if (mounted) {
        setState(() {
          _error = null;
          _chatBackground = 'custom';
          _chatBackgroundImagePath = path;
          _chatBackgroundImageUrl = url;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'We need a JPEG, PNG, WebP, or GIF under 10 MB for that background.');
      }
    }
  }

  Future<void> _pickCover() async {
    if (_uploadingProfileMedia) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
        maxHeight: 1200,
      );
      if (file == null) return;
      setState(() => _uploadingProfileMedia = true);
      final path =
          await Supa.uploadProfileCover(await file.readAsBytes(), file.name);
      if (!mounted) return;
      setState(() {
        _coverImagePath = path;
        _coverImageUrl = Supa.profileMediaUrl(path);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e,
            fallback: 'Choose a JPEG, PNG, or WebP image under 10 MB.'));
      }
    } finally {
      if (mounted) setState(() => _uploadingProfileMedia = false);
    }
  }

  Future<void> _pickProfileMusic() async {
    if (_uploadingProfileMedia) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'webm'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      setState(() => _uploadingProfileMedia = true);
      final path =
          await Supa.uploadProfileMusic(await file.readAsBytes(), file.name);
      if (!mounted) return;
      setState(() {
        _profileMusicPath = path;
        _profileMusicName = file.name;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e,
            fallback: 'Choose an audio file under 15 MB.'));
      }
    } finally {
      if (mounted) setState(() => _uploadingProfileMedia = false);
    }
  }

  Future<void> _pickAnimatedAvatar() async {
    if (_uploadingProfileMedia) return;
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      setState(() => _uploadingProfileMedia = true);
      final path =
          await Supa.uploadAnimatedAvatar(await file.readAsBytes(), file.name);
      if (!mounted) return;
      setState(() {
        _animatedAvatarPath = path;
        _animatedAvatarEnabled = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e,
            fallback: 'Choose an animated GIF avatar under 5 MB.'));
      }
    } finally {
      if (mounted) setState(() => _uploadingProfileMedia = false);
    }
  }

  Future<void> _save() async {
    if (_uploadingAvatar) return;
    final username = _username.text.trim();
    final profileColor = _profileColor.text.trim().toUpperCase();
    if (username.length < 3 ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
      setState(() => _error =
          'Usernames need at least 3 letters, numbers, dots, dashes, or underscores.');
      return;
    }
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(profileColor)) {
      setState(() =>
          _error = 'Profile color must be a six-digit hex value like #D4FF00.');
      return;
    }
    if (_password.text.isNotEmpty && _password.text.length < 6) {
      setState(() => _error = 'Use at least 6 characters for your password.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = "Those passwords don't match yet.");
      return;
    }
    final gameError = gameProfileError(
      platform: _gamePlatform,
      username: _gameUsername.text,
      status: _gameStatus.text,
    );
    if (gameError != null) {
      setState(() => _error = gameError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supa.updateProfile(
          username: username, displayName: _displayName.text);
      await Supa.updateProfileDetails(
          about: _about.text,
          photoVisibility: _photoVisibility,
          statusVisibility: _statusVisibility,
          aboutVisibility: _aboutVisibility,
          readReceiptsEnabled: _readReceiptsEnabled,
          defaultMessageExpiry: _defaultMessageExpiry,
          autoLockTimer: _autoLockTimer);
      await Supa.updateGameProfile(
        platform: _gamePlatform,
        username: _gamePlatform == null ? null : _gameUsername.text.trim(),
        status: _gamePlatform == null || _gameStatus.text.trim().isEmpty
            ? null
            : _gameStatus.text.trim(),
        visibility: _gameVisibility,
      );
      await Supa.updateProfileTheme(ProfileTheme(
        colorHex: profileColor,
        coverImagePath: _coverImagePath,
        musicPath: _profileMusicPath,
        musicName: _profileMusicName,
        animatedAvatarEnabled: _animatedAvatarEnabled,
        animatedAvatarPath: _animatedAvatarPath,
        statusMessage: _profileStatus.text.trim().isEmpty
            ? null
            : _profileStatus.text.trim(),
      ));
      await Supa.updateChatBackground(
        _chatBackground,
        imagePath:
            _chatBackground == 'custom' ? _chatBackgroundImagePath : null,
      );
      if (_password.text.isNotEmpty) {
        await Supa.client.auth
            .updateUser(UserAttributes(password: _password.text));
      }
      _password.clear();
      _confirmPassword.clear();
      await _loadProfile();
      _avatarUrlOverride = null;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(e,
            fallback:
                "We couldn't save those changes. If you picked a new username, it might already be taken."));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _settingsAvatar() => Avatar(
        name: _profile?.peerInitial ?? '?',
        url: _avatarUrlOverride ?? _profile?.avatarUrl,
        size: 96,
      );

  void _clearGameProfile() {
    setState(() {
      _gamePlatform = null;
      _gameUsername.clear();
      _gameStatus.clear();
    });
  }

  Color _profileColorValue() {
    final value = _profileColor.text.trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) return _P.primary;
    return Color(int.parse('FF${value.substring(1)}', radix: 16));
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _about.dispose();
    _profileStatus.dispose();
    _profileColor.dispose();
    _gameUsername.dispose();
    _gameStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ResponsiveAppShell(
        title: 'Settings',
        navIndex: 0,
        showBottomNavigation: false,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        body: _loading
            ? const FormSkeleton(label: 'Loading settings')
            : Center(
                child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Center(
                      child: Column(children: [
                    if (_avatarPreview case final bytes?)
                      ClipOval(
                        child: Image.memory(bytes,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _settingsAvatar()),
                      )
                    else if (_avatarUrlOverride == null &&
                        (_digitalAvatar?.enabled ?? false))
                      DigitalAvatar(config: _digitalAvatar!, size: 96)
                    else
                      _settingsAvatar(),
                    TextButton.icon(
                        onPressed:
                            _uploadingAvatar || _saving ? null : _pickAvatar,
                        icon: _uploadingAvatar
                            ? const BroSpinner(size: 16)
                            : const Icon(Icons.photo_camera_outlined),
                        label: Text(_uploadingAvatar
                            ? 'Uploading…'
                            : 'Change profile picture')),
                  ])),
                  const SizedBox(height: 16),
                  _SettingsField(
                      controller: _displayName,
                      label: 'Display name',
                      icon: Icons.badge_outlined),
                  const SizedBox(height: 14),
                  _SettingsField(
                      controller: _username,
                      label: 'Username',
                      icon: Icons.alternate_email),
                  const SizedBox(height: 14),
                  _SettingsField(
                      controller: _about,
                      label: 'About (max 160 characters)',
                      icon: Icons.info_outline),
                  const SizedBox(height: 20),
                  Text('Gaming profile',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      'Show friends your game handle and what you are playing.',
                      style: TextStyle(
                          color: _P.muted.withValues(alpha: 0.7),
                          fontSize: 12)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _gamePlatform,
                    decoration: const InputDecoration(labelText: 'Platform'),
                    hint: const Text('Not set'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Not set')),
                      for (final entry in gamePlatforms)
                        DropdownMenuItem(
                            value: entry.value, child: Text(entry.label)),
                    ],
                    onChanged: (v) => setState(() => _gamePlatform = v),
                  ),
                  const SizedBox(height: 12),
                  _SettingsField(
                      controller: _gameUsername,
                      label: 'Game username',
                      icon: Icons.sports_esports_outlined,
                      enabled: _gamePlatform != null),
                  const SizedBox(height: 12),
                  _SettingsField(
                      controller: _gameStatus,
                      label: 'Currently playing',
                      icon: Icons.videogame_asset_outlined,
                      enabled: _gamePlatform != null,
                      maxLength: gameStatusMaxLength),
                  if (_gamePlatform != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final game in suggestedGames)
                          ActionChip(
                            label: Text(game),
                            backgroundColor: _P.surfaceHigh,
                            side: BorderSide(
                                color: _P.border.withValues(alpha: 0.5)),
                            labelStyle: const TextStyle(
                                color: _P.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                            onPressed: () =>
                                setState(() => _gameStatus.text = game),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _gameVisibility,
                    decoration: const InputDecoration(
                        labelText: 'Gaming profile visible to'),
                    items: const [
                      DropdownMenuItem(
                          value: 'everyone', child: Text('Everyone')),
                      DropdownMenuItem(
                          value: 'contacts', child: Text('My contacts')),
                      DropdownMenuItem(value: 'nobody', child: Text('Nobody')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _gameVisibility = v);
                    },
                  ),
                  if (_gamePlatform != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _clearGameProfile,
                        icon:
                            const Icon(Icons.delete_outline_outlined, size: 16),
                        label: const Text('Clear gaming profile'),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text('Profile theme',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _profileColor,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 7,
                    style: const TextStyle(color: _P.text),
                    decoration: InputDecoration(
                      labelText: 'Profile color',
                      hintText: '#D4FF00',
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _profileColorValue(),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _profileStatus,
                    maxLength: 80,
                    style: const TextStyle(color: _P.text),
                    decoration: const InputDecoration(
                      labelText: 'Profile status message',
                      hintText: 'What are you up to?',
                      prefixIcon: Icon(Icons.short_text_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _uploadingProfileMedia ? null : _pickCover,
                    child: Container(
                      height: 132,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _P.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _P.border),
                        image: _coverImageUrl == null
                            ? null
                            : DecorationImage(
                                image: NetworkImage(_coverImageUrl!),
                                fit: BoxFit.cover,
                              ),
                      ),
                      child: _coverImageUrl == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.panorama_outlined, color: _P.muted),
                                SizedBox(height: 6),
                                Text('Upload cover image',
                                    style: TextStyle(color: _P.text)),
                                SizedBox(height: 3),
                                Text('JPEG, PNG, or WebP up to 10 MB',
                                    style: TextStyle(
                                        color: _P.muted, fontSize: 12)),
                              ],
                            )
                          : Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: FilledButton.tonalIcon(
                                  onPressed: _pickCover,
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Change cover'),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Enable message notifications'),
                      subtitle: const Text(
                          'Get a generic alert on this device, even when BRO is closed. Message text and sender stay hidden.'),
                      onTap: () async {
                        final ok = await PushNotifications.enable();
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok
                                  ? 'Notifications enabled on this device.'
                                  : 'Notifications unavailable. Check permission, network and device settings.')));
                      }),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.music_note_outlined),
                    title: Text(_profileMusicName ?? 'Profile music'),
                    subtitle: Text(
                        _profileMusicPath == null
                            ? 'Add a short track for visitors'
                            : 'Uploaded and ready to play',
                        style: TextStyle(color: _P.muted, fontSize: 12)),
                    trailing: TextButton(
                      onPressed:
                          _uploadingProfileMedia ? null : _pickProfileMusic,
                      child:
                          Text(_profileMusicPath == null ? 'Add' : 'Replace'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use animated avatar'),
                    subtitle: Text(
                      _animatedAvatarPath == null
                          ? 'Choose a GIF to enable this'
                          : 'Animated GIFs are shown as uploaded',
                      style: TextStyle(color: _P.muted, fontSize: 12),
                    ),
                    value:
                        _animatedAvatarEnabled && _animatedAvatarPath != null,
                    onChanged: _animatedAvatarPath == null
                        ? null
                        : (value) =>
                            setState(() => _animatedAvatarEnabled = value),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          _uploadingProfileMedia ? null : _pickAnimatedAvatar,
                      icon: const Icon(Icons.gif_box_outlined),
                      label: Text(_animatedAvatarPath == null
                          ? 'Choose animated GIF'
                          : 'Replace animated GIF'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.view_in_ar_outlined),
                    title: const Text('3D digital avatar'),
                    subtitle: Text(
                      (_digitalAvatar?.enabled ?? false)
                          ? 'Shown on your profile'
                          : 'Build a customizable avatar with reactions',
                      style: const TextStyle(color: _P.muted, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/digital-avatar'),
                  ),
                  const SizedBox(height: 20),
                  Text('Privacy',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  DropdownButtonFormField<String>(
                      initialValue: _photoVisibility,
                      decoration: const InputDecoration(
                          labelText: 'Profile photo visible to',
                          helperText:
                              'Applies in BRO. Direct image links are public.',
                          helperMaxLines: 2),
                      items: const [
                        DropdownMenuItem(
                            value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(
                            value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'nobody', child: Text('Nobody'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _photoVisibility = v);
                      }),
                  DropdownButtonFormField<String>(
                      initialValue: _statusVisibility,
                      decoration: const InputDecoration(
                          labelText: 'Online status visible to'),
                      items: const [
                        DropdownMenuItem(
                            value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(
                            value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'nobody', child: Text('Nobody'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _statusVisibility = v);
                      }),
                  DropdownButtonFormField<String>(
                      initialValue: _aboutVisibility,
                      decoration:
                          const InputDecoration(labelText: 'About visible to'),
                      items: const [
                        DropdownMenuItem(
                            value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(
                            value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'nobody', child: Text('Nobody'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _aboutVisibility = v);
                      }),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Close friends'),
                    subtitle: const Text(
                        'Choose who can see statuses shared with your private list'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/close-friends'),
                  ),
                  const SizedBox(height: 8),
                  Text('Messages',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Read receipts'),
                    subtitle: Text(
                      'Let others know when you have read their messages',
                      style: TextStyle(color: _P.muted, fontSize: 12),
                    ),
                    value: _readReceiptsEnabled,
                    onChanged: (v) => setState(() => _readReceiptsEnabled = v),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Duration?>(
                    initialValue: _defaultMessageExpiry,
                    decoration: const InputDecoration(
                        labelText: 'Default message timer'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Off')),
                      DropdownMenuItem(
                          value: Duration(hours: 24), child: Text('24 hours')),
                      DropdownMenuItem(
                          value: Duration(days: 7), child: Text('7 days')),
                      DropdownMenuItem(
                          value: Duration(days: 30), child: Text('30 days')),
                    ],
                    onChanged: (v) => setState(() => _defaultMessageExpiry = v),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Duration?>(
                    initialValue: _autoLockTimer,
                    decoration: const InputDecoration(
                        labelText: 'Auto-lock conversations'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Off')),
                      DropdownMenuItem(
                          value: Duration(minutes: 1), child: Text('1 minute')),
                      DropdownMenuItem(
                          value: Duration(minutes: 5),
                          child: Text('5 minutes')),
                      DropdownMenuItem(
                          value: Duration(minutes: 15),
                          child: Text('15 minutes')),
                      DropdownMenuItem(
                          value: Duration(minutes: 30),
                          child: Text('30 minutes')),
                      DropdownMenuItem(
                          value: Duration(hours: 1), child: Text('1 hour')),
                    ],
                    onChanged: (v) async {
                      setState(() => _autoLockTimer = v);
                      // When "Off" is selected, keep the cached timeout but
                      // lock with a short default so re-enabling is snappy.
                      await AppLock.setTimeoutSeconds(
                          v?.inSeconds ?? (await AppLock.timeoutSeconds()));
                    },
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices_outlined),
                    title: const Text('Linked devices'),
                    subtitle: const Text(
                        'Review active devices and sign out other sessions'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/settings/linked-devices'),
                  ),
                  const SizedBox(height: 8),
                  Text('Security',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppLock.enabled,
                    builder: (context, enabled, _) {
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('App Lock'),
                        subtitle: Text(
                          'Require biometrics or a PIN when you come back',
                          style: TextStyle(color: _P.muted, fontSize: 12),
                        ),
                        value: enabled,
                        onChanged: (v) async {
                          if (v && !await AppLock.hasPin()) {
                            if (!context.mounted) return;
                            final set = await promptSetPin(context);
                            if (!set) return;
                          }
                          await AppLock.setEnabled(v);
                          if (v) {
                            final timeout = await AppLock.timeoutSeconds();
                            final seconds = _autoLockTimer?.inSeconds ??
                                (timeout == 15 ? 60 : timeout);
                            await AppLock.setTimeoutSeconds(
                                seconds == 0 ? 60 : seconds);
                          }
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text('Chat background',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final option in _chatBackgroundOptions)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          setState(() => _chatBackground = option.$1);
                          try {
                            await Supa.updateChatBackground(option.$1);
                            Supa.notifyChatBackgroundChanged();
                          } catch (_) {}
                        },
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _P.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: _chatBackground == option.$1
                                    ? _P.primary
                                    : _P.border,
                                width: _chatBackground == option.$1 ? 2 : 1),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: option.$3),
                                      borderRadius: BorderRadius.circular(8),
                                    )),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(option.$2,
                                        style: const TextStyle(
                                            color: _P.text,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                    if (_chatBackground == option.$1)
                                      const Icon(Icons.check_circle_rounded,
                                          color: _P.primary, size: 14),
                                  ],
                                ),
                              ]),
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickChatBackground,
                      child: Container(
                        width: 112,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _P.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _chatBackground == 'custom'
                                  ? _P.primary
                                  : _P.border,
                              width: _chatBackground == 'custom' ? 2 : 1),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _P.surfaceHigh,
                                  borderRadius: BorderRadius.circular(8),
                                  image: _chatBackgroundImageUrl == null
                                      ? null
                                      : DecorationImage(
                                          image: NetworkImage(
                                              _chatBackgroundImageUrl!),
                                          fit: BoxFit.cover),
                                ),
                                child: _chatBackgroundImageUrl == null
                                    ? const Center(
                                        child: Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: _P.muted))
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      _chatBackgroundImagePath == null
                                          ? 'Upload image'
                                          : 'My image',
                                      style: const TextStyle(
                                          color: _P.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                  if (_chatBackground == 'custom')
                                    const Icon(Icons.check_circle_rounded,
                                        color: _P.primary, size: 14),
                                ],
                              ),
                            ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text('Change password',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  _SettingsField(
                      controller: _password,
                      label: 'New password',
                      icon: Icons.lock_outline,
                      obscure: true),
                  const SizedBox(height: 14),
                  _SettingsField(
                      controller: _confirmPassword,
                      label: 'Confirm new password',
                      icon: Icons.lock_outline,
                      obscure: true),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: SoftErrorBanner(message: _error!)),
                  const SizedBox(height: 22),
                  FilledButton(
                      onPressed: _saving || _uploadingAvatar ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _P.primary,
                        foregroundColor: _P.darkOnAccent,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: _saving
                          ? const BroSpinner(size: 20, color: _P.darkOnAccent)
                          : const Text('Save changes')),
                  const SizedBox(height: 12),
                  Center(
                      child: Text(Supa.currentUser?.email ?? '',
                          style: TextStyle(color: _P.muted, fontSize: 12))),
                  const SizedBox(height: 28),
                  Text('About',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                      buildNumber.isEmpty
                          ? 'BRO · development build'
                          : 'BRO · build $buildNumber',
                      style: const TextStyle(color: _P.muted, fontSize: 12)),
                ]),
              )),
      );
}

class _SettingsField extends StatefulWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.enabled = true,
    this.maxLength,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final bool enabled;
  final int? maxLength;

  @override
  State<_SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<_SettingsField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _obscured,
        enabled: widget.enabled,
        maxLength: widget.maxLength,
        style: const TextStyle(color: _P.text),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: _P.muted),
          prefixIcon: Icon(widget.icon, color: _P.muted),
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: _P.muted,
                  ),
                  tooltip: _obscured ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
          filled: true,
          fillColor: _P.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _P.primary, width: 1.5)),
        ),
      );
}

// ---------------------------------------------------------------------------
// User Profile Screen
// ---------------------------------------------------------------------------

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Profile? _profile;
  AvatarConfig? _digitalAvatar;
  bool _loading = true;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _followLoading = false;
  String? _error;
  final _profileMusicPlayer = AudioPlayer();
  bool _musicPlaying = false;

  bool get _isSelf => Supa.currentUser?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    _profileMusicPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _musicPlaying = false);
    });
    Presence.focus(widget.userId);
    _load();
  }

  @override
  void dispose() {
    Presence.unfocus(widget.userId);
    _profileMusicPlayer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        Supa.getProfile(widget.userId),
        if (!_isSelf) Supa.isFollowing(widget.userId),
        Supa.getFollowersCount(widget.userId),
        Supa.getFollowingCount(widget.userId),
        _safeDigitalAvatar(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Profile?;
        if (!_isSelf) _isFollowing = results[1] as bool;
        _followersCount = results[_isSelf ? 1 : 2] as int;
        _followingCount = results[_isSelf ? 2 : 3] as int;
        _digitalAvatar = results[_isSelf ? 3 : 4] as AvatarConfig?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "We couldn't open this profile right now.";
          _loading = false;
        });
      }
    }
  }

  /// The avatar config is optional: if the migration has not been applied yet
  /// the RPC is missing and the profile should still render.
  Future<AvatarConfig?> _safeDigitalAvatar(String uid) async {
    try {
      return await Supa.getDigitalAvatarConfig(uid);
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleMusic() async {
    final path = _profile?.theme.musicPath;
    if (path == null || path.isEmpty) return;
    try {
      if (_musicPlaying) {
        await _profileMusicPlayer.stop();
        if (mounted) setState(() => _musicPlaying = false);
        return;
      }
      await _profileMusicPlayer.play(
        UrlSource(Supa.profileMediaUrl(path)),
      );
      if (mounted) setState(() => _musicPlaying = true);
    } catch (_) {
      if (mounted) {
        setState(() => _musicPlaying = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("This profile track couldn't be played here."),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _followLoading = true);
    try {
      final newFollow = !_isFollowing;
      await Supa.setFollowing(widget.userId, newFollow);
      if (!mounted) return;
      setState(() {
        _isFollowing = newFollow;
        _followersCount += newFollow ? 1 : -1;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("We couldn't update that follow. Please try again."),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _openDM() async {
    try {
      final conv = await Supa.getOrCreateDM(widget.userId);
      if (mounted) context.go('/chat/${conv.id}', extra: _profile);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("We couldn't open that chat. Please try again."),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showFollowersSheet({required bool startOnFollowing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowersFollowingScreen(
          userId: widget.userId,
          initialTab: startOnFollowing ? 1 : 0,
          onOpenProfile: (uid) => context.push('/profile/$uid'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        leading: const BackButton(color: _P.text),
        title: _profile == null
            ? null
            : Text(
                _profile!.label,
                style: const TextStyle(
                    color: _P.text, fontWeight: FontWeight.w700, fontSize: 17),
              ),
      ),
      body: _loading
          ? const FormSkeleton(label: 'Loading profile')
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off_outlined,
                          size: 48, color: _P.muted),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: _P.muted, fontSize: 15)),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final profile = _profile!;
    final isMe = _isSelf;
    final themeColor = _profileThemeColor(profile.theme);
    final avatarUrl = profile.theme.animatedAvatarEnabled &&
            profile.theme.animatedAvatarPath != null
        ? Supa.profileMediaUrl(profile.theme.animatedAvatarPath!)
        : profile.avatarUrl;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (profile.theme.coverImagePath != null) ...[
            const SizedBox(height: 12),
            Container(
              height: 176,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: DecorationImage(
                  image: NetworkImage(
                      Supa.profileMediaUrl(profile.theme.coverImagePath!)),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.2), BlendMode.darken),
                ),
                border: Border.all(color: themeColor.withValues(alpha: 0.55)),
              ),
            ),
          ],
          // ── Avatar & name ──────────────────────────────────────────────
          const SizedBox(height: 28),
          Center(
            child: Stack(
              children: [
                if (_digitalAvatar?.enabled ?? false)
                  DigitalAvatar(
                    config: _digitalAvatar!,
                    size: 104,
                  )
                else
                  Avatar(
                    name: profile.peerInitial,
                    url: avatarUrl,
                    size: 92,
                  ),
                // Subtle glow ring
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: themeColor.withValues(alpha: 0.55),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            profile.label,
            style: const TextStyle(
                color: _P.text, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '@${profile.username}',
            style: TextStyle(color: _P.muted, fontSize: 14),
          ),
          if (!isMe) ...[
            const SizedBox(height: 6),
            ValueListenableBuilder<int>(
              valueListenable: Presence.epoch,
              builder: (_, __, ___) {
                final presence = Presence.label(profile.id);
                if (presence == null) return const SizedBox.shrink();
                final online = Presence.isOnline(profile.id);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: online ? _P.success : _P.muted,
                        shape: BoxShape.circle,
                        boxShadow: online
                            ? [
                                BoxShadow(
                                  color: _P.success.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    Text(
                      presence,
                      style: TextStyle(
                        color: online ? _P.success : _P.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          _GamePresenceCard(profile: profile),
          const SizedBox(height: 20),

          // ── Follower / following counts ─────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProfileStatChip(
                label: 'Followers',
                count: _followersCount,
                onTap: () => _showFollowersSheet(startOnFollowing: false),
              ),
              const SizedBox(width: 24),
              _ProfileStatChip(
                label: 'Following',
                count: _followingCount,
                onTap: () => _showFollowersSheet(startOnFollowing: true),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Action buttons (only for other users) ───────────────────────
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _isFollowing ? _P.surfaceHigh : _P.primary,
                        foregroundColor:
                            _isFollowing ? _P.text : _P.darkOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _followLoading ? null : _toggleFollow,
                      icon: _followLoading
                          ? BroSpinner(
                              size: 16,
                              color: _isFollowing ? _P.text : _P.darkOnAccent,
                            )
                          : Icon(
                              _isFollowing
                                  ? Icons.person_remove_outlined
                                  : Icons.person_add_outlined,
                              size: 18,
                            ),
                      label: Text(
                        _isFollowing ? 'Unfollow' : 'Follow',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _P.text,
                        side: const BorderSide(color: _P.border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _openDM,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Message',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ] else ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit profile'),
              style: TextButton.styleFrom(foregroundColor: _P.primary),
            ),
            const SizedBox(height: 28),
          ],

          if (profile.theme.statusMessage != null &&
              profile.theme.statusMessage!.trim().isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: themeColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_outlined, color: themeColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      profile.theme.statusMessage!.trim(),
                      style:
                          TextStyle(color: _P.text, fontSize: 14, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (profile.theme.musicPath != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _P.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: themeColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.music_note_outlined, color: themeColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profile.theme.musicName ?? 'Profile music',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _P.text, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: _musicPlaying ? 'Stop music' : 'Play music',
                    onPressed: _toggleMusic,
                    icon: Icon(
                      _musicPlaying
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      color: themeColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── About section ──────────────────────────────────────────────
          if (profile.about != null && profile.about!.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'About',
                  style: TextStyle(
                    color: _P.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _P.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _P.border.withValues(alpha: 0.5)),
              ),
              width: double.infinity,
              child: Text(
                profile.about!.trim(),
                style: TextStyle(
                    color: _P.text.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.5),
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── Joined date ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 13, color: _P.muted.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  'Joined ${_fmtJoined(profile.createdAt)}',
                  style: TextStyle(
                      color: _P.muted.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  static String _fmtJoined(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// Small tappable stat chip used in the profile page
class _ProfileStatChip extends StatelessWidget {
  const _ProfileStatChip(
      {required this.label, required this.count, required this.onTap});
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _fmt(count),
            style: const TextStyle(
                color: _P.text, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: _P.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// Gaming presence card shown on a profile when the viewer may see it.
class _GamePresenceCard extends StatelessWidget {
  const _GamePresenceCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Presence.epoch,
      builder: (_, __, ___) {
        final game =
            Presence.game(profile.id) ?? GamePresence.fromProfile(profile);
        if (!game.isVisible) return const SizedBox.shrink();
        final color = _profileThemeColor(profile.theme);
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _P.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(Icons.sports_esports_outlined, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (game.playingLabel != null) ...[
                      Text(game.playingLabel!,
                          style: const TextStyle(
                              color: _P.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                    ],
                    Text(game.handleLabel ?? '',
                        style: TextStyle(color: _P.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Followers / Following Sheet
// ---------------------------------------------------------------------------

class _FollowersFollowingSheet extends StatefulWidget {
  const _FollowersFollowingSheet({
    required this.userId,
    required this.onOpenProfile,
  });
  final String userId;
  final void Function(String userId) onOpenProfile;

  @override
  State<_FollowersFollowingSheet> createState() =>
      _FollowersFollowingSheetState();
}

class _FollowersFollowingSheetState extends State<_FollowersFollowingSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Profile>? _followers;
  List<Profile>? _following;
  bool _loadingFollowers = true;
  bool _loadingFollowing = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: 0);
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    try {
      final list = await Supa.getFollowers(widget.userId);
      if (mounted) {
        setState(() {
          _followers = list;
          _loadingFollowers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _followers = [];
          _loadingFollowers = false;
        });
      }
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final list = await Supa.getFollowing(widget.userId);
      if (mounted) {
        setState(() {
          _following = list;
          _loadingFollowing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _following = [];
          _loadingFollowing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _P.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabs,
            labelColor: _P.primary,
            unselectedLabelColor: _P.muted,
            indicatorColor: _P.primary,
            indicatorWeight: 2.5,
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            tabs: [
              Tab(
                text: 'Followers'
                    '${_followers != null ? '  ${_fmt(_followers!.length)}' : ''}',
              ),
              Tab(
                text: 'Following'
                    '${_following != null ? '  ${_fmt(_following!.length)}' : ''}',
              ),
            ],
          ),
          const Divider(height: 1, color: _P.border),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildList(_followers, _loadingFollowers, scrollCtrl),
                _buildList(_following, _loadingFollowing, scrollCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
      List<Profile>? profiles, bool loading, ScrollController scrollCtrl) {
    if (loading) {
      return const ListSkeleton(label: 'Loading people');
    }
    if (profiles == null || profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 44, color: _P.muted),
            const SizedBox(height: 10),
            Text('Nobody here yet',
                style: TextStyle(color: _P.muted, fontSize: 14)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: profiles.length,
      itemBuilder: (_, i) {
        final p = profiles[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Avatar(name: p.peerInitial, url: p.avatarUrl, size: 42),
          title: Text(p.label,
              style:
                  const TextStyle(color: _P.text, fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('@${p.username}',
                  style: TextStyle(color: _P.muted, fontSize: 12)),
              if (GamePresence.fromProfile(p).isVisible)
                Text(
                  GamePresence.fromProfile(p).playingLabel ??
                      '@${p.gameUsername}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _P.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ),
          trailing: p.id == Supa.currentUser?.id
              ? null
              : _FollowToggleButton(userId: p.id),
          onTap: () => widget.onOpenProfile(p.id),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
      },
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// A small follow/unfollow toggle button used inside list tiles.
class _FollowToggleButton extends StatefulWidget {
  const _FollowToggleButton({required this.userId});
  final String userId;

  @override
  State<_FollowToggleButton> createState() => _FollowToggleButtonState();
}

class _FollowToggleButtonState extends State<_FollowToggleButton> {
  bool? _following; // null = loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Supa.isFollowing(widget.userId).then((v) {
      if (mounted) setState(() => _following = v);
    }).catchError((_) {
      if (mounted) setState(() => _following = false);
    });
  }

  Future<void> _toggle() async {
    final current = _following;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Supa.setFollowing(widget.userId, !current);
      if (mounted) setState(() => _following = !current);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_following == null) {
      return const BroSpinner(size: 18);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _busy
          ? const BroSpinner(key: ValueKey('busy'), size: 18)
          : OutlinedButton(
              key: ValueKey(_following),
              onPressed: _toggle,
              style: OutlinedButton.styleFrom(
                foregroundColor: _following! ? _P.muted : _P.primary,
                side: BorderSide(
                    color: _following! ? _P.border : _P.primary, width: 1.2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(80, 32),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_following! ? 'Following' : 'Follow'),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned Messages Banner
// ---------------------------------------------------------------------------

/// A compact banner shown at the top of the chat when at least one message is
/// pinned.  Tapping it cycles through pinned messages and scrolls to each one
/// in the list.  Long-pressing opens a full sheet of all pinned messages.
/// The × button hides the banner for the current session (without unpinning).
