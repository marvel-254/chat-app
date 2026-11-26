import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart' as app_colors;
import '../models/profile.dart';
import '../services/status_feed.dart';
import '../services/supabase.dart';
import '../ui/errors.dart';
import '../ui/states.dart';

const _statusViewDuration = Duration(minutes: 2, seconds: 30);

class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({
    super.key,
    required this.userId,
    this.peerUserIds = const [],
    this.loadStatuses = Supa.fetchStatusesOnce,
    this.recordView = Supa.recordStatusView,
    this.currentUserId = _currentUserId,
  });

  final String userId;
  final List<String> peerUserIds;
  final Future<List<StatusPost>> Function() loadStatuses;
  final Future<void> Function(String statusId) recordView;
  final String? Function() currentUserId;

  static String? _currentUserId() => Supa.currentUser?.id;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  List<StatusPost> _posts = [];
  int _index = 0;
  bool _loading = true;
  String? _error;
  bool _paused = false;
  final FocusNode _keyFocus = FocusNode(debugLabel: 'status-viewer');

  StatusPost? get _current =>
      _posts.isEmpty ? null : _posts[_index.clamp(0, _posts.length - 1)];

  bool get _isMine => widget.userId == widget.currentUserId();

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: _statusViewDuration,
      // Reduced motion must not shorten the time available to read a status.
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _load();
  }

  Future<void> _load() async {
    try {
      // One-shot REST fetch: the viewer doesn't need live updates, and this
      // keeps it working even when the realtime channel is slow or down.
      final posts = await widget.loadStatuses().timeout(
            const Duration(seconds: 10),
          );
      final mine = posts
          .where((p) => p.userId == widget.userId)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (!mounted) return;
      setState(() {
        _posts = mine;
        _loading = false;
        _error = mine.isEmpty ? 'This status expired.' : null;
      });
      if (mine.isNotEmpty) {
          _progress.forward(from: 0);
          // Record view for the first status
          unawaited(widget.recordView(mine.first.id));
        }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e,
            fallback: "We couldn't open that status.");
      });
    }
  }

  @override
  void dispose() {
    _keyFocus.dispose();
    _progress.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _previous();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _next();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (_paused) {
        _resume();
      } else {
        _pause();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && mounted && context.canPop()) {
      context.pop();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && _isMine) {
      unawaited(_delete());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _next() {
    if (_index + 1 < _posts.length) {
      setState(() => _index++);
      _progress.forward(from: 0);
      unawaited(widget.recordView(_posts[_index].id));
      return;
    }
    final ids = widget.peerUserIds.where((id) => id != widget.userId).toList();
    final pos = widget.peerUserIds.indexOf(widget.userId);
    if (pos >= 0 && pos + 1 < widget.peerUserIds.length) {
      context.pushReplacement('/status/view/${widget.peerUserIds[pos + 1]}',
          extra: widget.peerUserIds);
      return;
    }
    if (ids.isNotEmpty && pos < 0) {
      context.pop();
      return;
    }
    if (mounted) context.pop();
  }

  void _previous() {
    if (_index > 0) {
      setState(() => _index--);
      _progress.forward(from: 0);
      unawaited(widget.recordView(_posts[_index].id));
      return;
    }
    final pos = widget.peerUserIds.indexOf(widget.userId);
    if (pos > 0) {
      context.pushReplacement('/status/view/${widget.peerUserIds[pos - 1]}',
          extra: widget.peerUserIds);
      return;
    }
    if (mounted) context.pop();
  }

  void _pause() {
    _paused = true;
    _progress.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    _progress.forward();
  }

  Future<void> _delete() async {
    final post = _current;
    if (post == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this status?'),
        content: const Text("It'll disappear for everyone right away."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supa.deleteStatus(post.id);
      if (!mounted) return;
      context.go('/status');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyErrorMessage(e,
              fallback: "We couldn't delete that."))));
    }
  }

  Future<void> _reply() async {
    try {
      final conv = await Supa.getOrCreateDM(widget.userId);
      if (mounted) context.go('/chat/${conv.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyErrorMessage(e,
              fallback: "We couldn't open that chat."))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _current;
    return Focus(
      autofocus: true,
      focusNode: _keyFocus,
      onKeyEvent: _onKeyEvent,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
        backgroundColor: app_colors.P.bg,
        body: _loading
            ? const AppLoader()
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: app_colors.P.muted, fontSize: 16)),
                    ),
                  )
                : GestureDetector(
                    onLongPressStart: (_) => _pause(),
                    onLongPressEnd: (_) => _resume(),
                    onVerticalDragEnd: (d) {
                      if (d.primaryVelocity != null && d.primaryVelocity! > 280) {
                        context.pop();
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Backdrop(post: post!),
                        Row(
                          children: [
                            Expanded(
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Semantics(
                                  label: 'Previous status',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _previous,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Semantics(
                                  label: 'Next status',
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _next,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SafeArea(
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                                child: Row(
                                  children: [
                                    for (var i = 0; i < _posts.length; i++) ...[
                                      if (i > 0) const SizedBox(width: 4),
                                      Expanded(
                                        child: AnimatedBuilder(
                                          animation: _progress,
                                          builder: (_, __) {
                                            final value = i < _index
                                                ? 1.0
                                                : i == _index
                                                    ? _progress.value
                                                    : 0.0;
                                            return ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                              child: LinearProgressIndicator(
                                                value: value,
                                                minHeight: 3,
                                                backgroundColor:
                                                    Colors.white24,
                                                color: Colors.white,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundImage:
                                      (post.userAvatarUrl ?? '').isEmpty
                                          ? null
                                          : NetworkImage(post.userAvatarUrl!),
                                  backgroundColor: app_colors.surfaceHigh,
                                  child: (post.userAvatarUrl ?? '').isEmpty
                                      ? Text(post.userInitial,
                                          style: const TextStyle(
                                              color: app_colors.P.text,
                                              fontWeight: FontWeight.w700))
                                      : null,
                                ),
                                title: Text(post.userLabel,
                                    style: const TextStyle(
                                        color: app_colors.P.text,
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '${statusTimeAgo(post.createdAt, DateTime.now())} · ${statusTimeLeft(post.expiresAt, DateTime.now())}',
                                  style: const TextStyle(
                                      color: app_colors.P.muted, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isMine)
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: _delete,
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.white),
                                      ),
                                    IconButton(
                                      tooltip: 'Close',
                                      onPressed: () => context.pop(),
                                      icon: const Icon(Icons.close,
                                          color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (!_isMine)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                  child: FilledButton.tonalIcon(
                                    onPressed: _reply,
                                    icon: const Icon(Icons.reply),
                                    label: const Text('Reply in chat'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.12),
                                      foregroundColor: app_colors.P.text,
                                      minimumSize: const Size.fromHeight(48),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.post});
  final StatusPost post;

  @override
  Widget build(BuildContext context) {
    final colors = app_colors.statusBackdrops[
        post.userId.hashCode.abs() % app_colors.statusBackdrops.length];
    final media = Supa.statusMediaUrl(post.mediaPath);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (media != null)
          Image.network(media, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _wash(colors))
        else
          _wash(colors),
        Container(color: Colors.black.withValues(alpha: 0.22)),
        if (post.mood != null)
          Positioned(
            top: 120,
            left: 0,
            right: 0,
            child: Text(post.mood!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 64)),
          ),
        if (post.hasText)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                post.content!.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _wash(List<Color> colors) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
}
