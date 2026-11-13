import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../services/status_feed.dart';
import '../services/supabase.dart';
import '../ui/errors.dart';

class _C {
  static const bg = Color(0xFF121318);
  static const surface = Color(0xFF1E1F25);
  static const surfaceHigh = Color(0xFF292A2F);
  static const border = Color(0xFF444932);
  static const text = Color(0xFFE3E1E9);
  static const muted = Color(0xFFC5C9AC);
  static const primary = Color(0xFFD4FF00);
  static const darkOnAccent = Color(0xFF0C0D12);
}

const _moods = ['🔥', '😊', '💭', '🎉', '😴', '💪', '❤️', '✨'];

class StatusComposerScreen extends StatefulWidget {
  const StatusComposerScreen({super.key});

  @override
  State<StatusComposerScreen> createState() => _StatusComposerScreenState();
}

class _StatusComposerScreenState extends State<StatusComposerScreen> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _photo;
  String? _photoName;
  String? _mood;
  String _privacy = 'contacts';
  bool _posting = false;

  bool get _canPost =>
      !_posting &&
      ((_text.text.trim().isNotEmpty) || _photo != null || _mood != null);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
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
          fallback: "We couldn't open that photo. Try another one."));
    }
  }

  Future<void> _post() async {
    if (!_canPost) return;
    setState(() => _posting = true);
    try {
      String? mediaPath;
      if (_photo != null) {
        mediaPath = await Supa.uploadStatusMedia(
            _photo!, _photoName ?? 'status.jpg');
      }
      await Supa.createStatus(
        content: _text.text.trim().isEmpty ? null : _text.text.trim(),
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
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        title: const Text('New status'),
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 18, color: _C.muted),
                  const SizedBox(width: 6),
                  Text(statusPrivacyLabel(_privacy),
                      style: const TextStyle(color: _C.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _canPost ? _post : null,
              style: FilledButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.darkOnAccent,
                disabledBackgroundColor: _C.surfaceHigh,
              ),
              child: _posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post',
                      style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AspectRatio(
            aspectRatio: 9 / 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_photo != null)
                    Image.memory(_photo!, fit: BoxFit.cover)
                  else
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF1A1C12), Color(0xFF2A3208)],
                        ),
                      ),
                    ),
                  Container(color: Colors.black.withValues(alpha: 0.18)),
                  if (_mood != null)
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Text(_mood!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 56)),
                    ),
                  if (_text.text.trim().isNotEmpty)
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _text.text.trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 12)
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLength: 280,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(color: _C.text),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'A thought, a mood, a moment…',
              hintStyle: const TextStyle(color: _C.muted),
              filled: true,
              fillColor: _C.surface,
              counterStyle: const TextStyle(color: _C.muted, fontSize: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _C.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _C.border),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mood in _moods)
                ChoiceChip(
                  label: Text(mood, style: const TextStyle(fontSize: 18)),
                  selected: _mood == mood,
                  onSelected: (on) =>
                      setState(() => _mood = on ? mood : null),
                  selectedColor: _C.primary.withValues(alpha: 0.22),
                  backgroundColor: _C.surface,
                  side: const BorderSide(color: _C.border),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ),
              if (_photo != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Remove photo',
                  onPressed: () => setState(() {
                    _photo = null;
                    _photoName = null;
                  }),
                  icon: const Icon(Icons.close, color: _C.muted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Visible to ${statusPrivacyLabel(_privacy).toLowerCase()}. Disappears in 24 hours.',
            style: const TextStyle(color: _C.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}
