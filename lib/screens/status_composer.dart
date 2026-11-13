import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../services/status_feed.dart';
import '../services/supabase.dart';
import '../ui/errors.dart';

class _C {
  static const bg = Color(0xFF050505);
  static const surface = Color(0xFF1E1F25);
  static const text = Color(0xFFE3E1E9);
  static const muted = Color(0xFFC5C9AC);
  static const primary = Color(0xFFD4FF00);
  static const darkOnAccent = Color(0xFF0C0D12);
}

const _moods = ['🔥', '😊', '💭', '🎉', '😴', '💪', '❤️', '✨'];

const _washes = <List<Color>>[
  [Color(0xFF1A1C12), Color(0xFF3D4A00)],
  [Color(0xFF102438), Color(0xFF0D1724)],
  [Color(0xFF241018), Color(0xFF4A1530)],
  [Color(0xFF142A24), Color(0xFF0E1B19)],
];

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
      context.go('/status');
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

  @override
  Widget build(BuildContext context) {
    final colors = _washes[_wash % _washes.length];
    return Scaffold(
      backgroundColor: _C.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Who can see this',
            initialValue: _privacy,
            onSelected: (v) => setState(() => _privacy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'everyone', child: Text('Everyone')),
              PopupMenuItem(value: 'contacts', child: Text('Contacts')),
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
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
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
                          height: 1.25),
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
                  children: [
                    for (final mood in _moods)
                      GestureDetector(
                        onTap: () => setState(
                            () => _mood = _mood == mood ? null : mood),
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: _mood == mood
                              ? _C.primary.withValues(alpha: 0.35)
                              : Colors.black38,
                          child: Text(mood, style: const TextStyle(fontSize: 18)),
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
                      style: const TextStyle(color: _C.text),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Add a caption',
                        hintStyle: const TextStyle(color: _C.muted),
                        filled: true,
                        fillColor: _C.surface.withValues(alpha: 0.92),
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
                          onPressed: () =>
                              setState(() => _wash = (_wash + 1) % _washes.length),
                          icon: const Icon(Icons.palette_outlined),
                        ),
                      ],
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _canPost ? _post : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _C.primary,
                          foregroundColor: _C.darkOnAccent,
                          disabledBackgroundColor: Colors.white24,
                        ),
                        icon: _posting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        label: const Text('Post',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Visible to ${statusPrivacyLabel(_privacy).toLowerCase()} · 24 hours',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
