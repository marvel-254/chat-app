import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../models/profile.dart';
import '../../ui/states.dart';
import '../../ui/errors.dart';
import '../lock_gate.dart';
import '../../services/presence.dart';
import '../../followers_following_screen.dart';
import '../../app_constants.dart';
import '../../services/app_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chat/widgets/avatar.dart';

const _bg = app_colors.bg;
const _surface = app_colors.surface;
const _surfaceHigh = app_colors.surfaceHigh;
const _surfaceLow = app_colors.surfaceLow;
const _border = app_colors.border;
const _text = app_colors.text;
const _muted = app_colors.muted;
const _success = app_colors.success;
const _volt = app_colors.volt;
const _darkOnVolt = app_colors.darkOnVolt;
const _chatBackgroundOptions = app_colors.chatBackgroundOptions;

class _P {
  static const bg = app_colors.bg;
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const surfaceLow = app_colors.surfaceLow;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const success = app_colors.success;
  static const primary = app_colors.volt;
  static const volt = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
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
  Profile? _profile;
  XFile? _avatarFile;
  String? _avatarUrlOverride;
  bool _uploadingAvatar = false;
  String _chatBackground = 'default';
  String? _chatBackgroundImagePath;
  String? _chatBackgroundImageUrl;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _photoVisibility = 'everyone';
  String _statusVisibility = 'everyone';
  String _aboutVisibility = 'everyone';
  bool _readReceiptsEnabled = true;
  Duration? _defaultMessageExpiry;
  Duration? _autoLockTimer;

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
      _photoVisibility = profile?.photoVisibility ?? 'everyone';
      _statusVisibility = profile?.statusVisibility ?? 'everyone';
      _aboutVisibility = profile?.aboutVisibility ?? 'everyone';
      _readReceiptsEnabled = profile?.readReceiptsEnabled ?? true;
      _defaultMessageExpiry = profile?.defaultMessageExpiry;
      _autoLockTimer = profile?.autoLockTimer;
      _chatBackground = profile?.chatBackground ?? 'default';
      _chatBackgroundImagePath = profile?.chatBackgroundImagePath;
      if (_chatBackgroundImagePath != null) {
        _chatBackgroundImageUrl =
            await Supa.chatBackgroundUrl(_chatBackgroundImagePath!);
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
    if (_uploadingAvatar) return;
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (file == null || !mounted) return;
    setState(() {
      _avatarFile = file;
      _error = null;
      _uploadingAvatar = true;
    });
    try {
      final url = await Supa.uploadAvatar(await file.readAsBytes(), file.name);
      if (!mounted) return;
      setState(() {
        _avatarUrlOverride = url;
        _avatarFile = null;
        _uploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _error = friendlyErrorMessage(e,
            fallback:
                "We couldn't update your photo. Try a JPEG, PNG, WebP, or GIF under 5 MB.");
      });
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_background', 'custom');
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

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.length < 3 ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
      setState(() => _error =
          'Usernames need at least 3 letters, numbers, dots, dashes, or underscores.');
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
      await Supa.updateChatBackground(
        _chatBackground,
        imagePath:
            _chatBackground == 'custom' ? _chatBackgroundImagePath : null,
      );
      if (_avatarFile != null) {
        await Supa.uploadAvatar(
            await _avatarFile!.readAsBytes(), _avatarFile!.name);
      }
      if (_password.text.isNotEmpty) {
        await Supa.client.auth
            .updateUser(UserAttributes(password: _password.text));
      }
      _password.clear();
      _confirmPassword.clear();
      await _loadProfile();
      _avatarFile = null;
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

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Settings'),
            leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop())),
        body: _loading
            ? const FormSkeleton(label: 'Loading settings')
            : Center(
                child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Center(
                      child: Column(children: [
                    FutureBuilder<List<int>>(
                      future: _avatarFile?.readAsBytes(),
                      builder: (_, snap) => _avatarFile != null && snap.hasData
                          ? CircleAvatar(
                              radius: 48,
                              backgroundImage:
                                  MemoryImage(Uint8List.fromList(snap.data!)))
                          : Avatar(
                              name: _profile?.peerInitial ?? '?',
                              url: _avatarUrlOverride ?? _profile?.avatarUrl,
                              size: 96),
                    ),
                    TextButton.icon(
                        onPressed: _uploadingAvatar ? null : _pickAvatar,
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
                  Text('Privacy',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  DropdownButtonFormField<String>(
                      initialValue: _photoVisibility,
                      decoration: const InputDecoration(
                          labelText: 'Profile photo visible to'),
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
                      await AppLock.setTimeoutSeconds(v?.inSeconds ??
                          (await AppLock.timeoutSeconds()));
                    },
                  ),
                  const SizedBox(height: 20),
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
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('chat_background', option.$1);
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
                      onPressed: _saving ? null : _save,
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
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;

  @override
  State<_SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<_SettingsField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _obscured,
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
  bool _loading = true;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _followLoading = false;
  String? _error;

  bool get _isSelf => Supa.currentUser?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    Presence.focus(widget.userId);
    _load();
  }

  @override
  void dispose() {
    Presence.unfocus(widget.userId);
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
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Profile?;
        if (!_isSelf) _isFollowing = results[1] as bool;
        _followersCount = results[_isSelf ? 1 : 2] as int;
        _followingCount = results[_isSelf ? 2 : 3] as int;
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar & name ──────────────────────────────────────────────
          const SizedBox(height: 28),
          Center(
            child: Stack(
              children: [
                Avatar(
                  name: profile.peerInitial,
                  url: profile.avatarUrl,
                  size: 92,
                ),
                // Subtle glow ring
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _P.primary.withValues(alpha: 0.35),
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
          subtitle: Text('@${p.username}',
              style: TextStyle(color: _P.muted, fontSize: 12)),
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
