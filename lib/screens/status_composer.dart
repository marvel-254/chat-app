import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart' as app_colors;
import '../services/status_feed.dart';
import '../services/supabase.dart';
import '../ui/errors.dart';
import '../ui/states.dart';
import '../widgets/responsive_app_shell.dart';

const _moods = ['🔥', '😊', '💭', '🎉', '😴', '💪', '❤️', '✨'];

class StatusComposerScreen extends StatefulWidget {
  const StatusComposerScreen({super.key, this.initialSource});

  /// `camera`, `gallery`, or `text`.
  final String? initialSource;

  @override
  State<StatusComposerScreen> createState() => _StatusComposerScreenState();
}

class _StatusComposerScreenState extends State<StatusComposerScreen> {
  final _text = TextEditingController();
  final _caption = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _photo;
  String? _photoName;
  String? _mood;
  String _privacy = 'contacts';
  bool _posting = false;
  int _wash = 0;
  bool _picking = false;

  bool get _canPost =>
      !_posting &&
      ((_text.text.trim().isNotEmpty) ||
          _caption.text.trim().isNotEmpty ||
          _photo != null ||
          _mood != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    switch (widget.initialSource) {
      case 'camera':
        await _pick(ImageSource.camera);
      case 'gallery':
        await _pick(ImageSource.gallery);
      default:
        break;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking) return;
    _picking = true;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _photoName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyErrorMessage(e,
          fallback: "We couldn't open the camera. Try the gallery instead."));
    } finally {
      _picking = false;
    }
  }

  Future<void> _post() async {
    if (!_canPost) return;
    setState(() => _posting = true);
    try {
      String? mediaPath;
      if (_photo != null) {
        mediaPath =
            await Supa.uploadStatusMedia(_photo!, _photoName ?? 'status.jpg');
      }
      final body = _photo != null ? _caption.text.trim() : _text.text.trim();
      await Supa.createStatus(
        content: body.isEmpty ? null : body,
        mediaPath: mediaPath,
        mood: _mood,
        privacy: _privacy,
      );
      if (!mounted) return;
      // Confirm before navigating so the user knows the post landed even if
      // the feed takes a moment to refresh.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status posted')),
      );
      context.go('/status');
    } on ArgumentError catch (e) {
      if (!mounted) return;
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyErrorMessage(e,
          fallback: "That status didn't post. Try again."));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _privacyMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Who can see this',
      initialValue: _privacy,
      onSelected: (value) => setState(() => _privacy = value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'everyone', child: Text('Everyone')),
        PopupMenuItem(value: 'contacts', child: Text('Contacts')),
        PopupMenuItem(value: 'close_friends', child: Text('Close friends')),
        PopupMenuItem(value: 'followers', child: Text('Followers')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 18),
            const SizedBox(width: 6),
            Text(statusPrivacyLabel(_privacy),
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors =
        app_colors.statusWashes[_wash % app_colors.statusWashes.length];
    final composer = Stack(
      fit: StackFit.expand,
      children: [
        if (_photo != null)
          Image.memory(_photo!, fit: BoxFit.cover)
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
        Container(color: Colors.black.withValues(alpha: 0.18)),
        SafeArea(
          child: Column(
            children: [
              const Spacer(),
              if (_mood != null)
                Text(_mood!, style: const TextStyle(fontSize: 64)),
              if (_photo == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    controller: _text,
                    maxLength: 280,
                    maxLines: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: 'Tap to write…',
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 24),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final mood in _moods)
                    Tooltip(
                      message: 'Add mood',
                      child: InkWell(
                        onTap: () => setState(
                          () => _mood = _mood == mood ? null : mood,
                        ),
                        customBorder: const CircleBorder(),
                        hoverColor: app_colors.volt.withValues(alpha: 0.12),
                        focusColor: app_colors.volt.withValues(alpha: 0.16),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _mood == mood
                                  ? app_colors.volt
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: _mood == mood
                                ? app_colors.volt.withValues(alpha: 0.35)
                                : Colors.black38,
                            child: Text(
                              mood,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_photo != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _caption,
                    maxLength: 140,
                    style: const TextStyle(color: app_colors.P.text),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Add a caption',
                      hintStyle: const TextStyle(color: app_colors.P.muted),
                      filled: true,
                      fillColor: app_colors.P.surface.withValues(alpha: 0.92),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Camera',
                      onPressed: () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Gallery',
                      onPressed: () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_outlined),
                    ),
                    if (_photo == null) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Change colour',
                        onPressed: () => setState(
                          () => _wash = (_wash + 1) %
                              app_colors.statusWashes.length,
                        ),
                        icon: const Icon(Icons.palette_outlined),
                      ),
                    ],
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _canPost ? _post : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: app_colors.P.primary,
                        foregroundColor: app_colors.P.darkOnAccent,
                        disabledBackgroundColor: Colors.white24,
                      ),
                      icon: _posting
                          ? const BroSpinner(
                              size: 16,
                              color: app_colors.P.darkOnAccent,
                            )
                          : const Icon(Icons.send),
                      label: const Text(
                        'Post',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Visible to ${statusPrivacyLabel(_privacy).toLowerCase()} · $statusLifetimeHours hours',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );

    return ResponsiveAppShell(
      title: 'New status',
      subtitle: 'Share a moment with your people',
      navIndex: 2,
      showBottomNavigation: false,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [_privacyMenu()],
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < app_colors.desktopBreakpoint) {
          return composer;
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              height: constraints.maxHeight * 0.88,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: app_colors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: composer,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
