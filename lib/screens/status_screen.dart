import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/profile.dart';
import '../services/status_feed.dart';
import '../services/supabase.dart';
import '../ui/errors.dart';
import '../ui/states.dart';
import '../widgets/home_nav_bar.dart';
import '../widgets/status_ring_avatar.dart';

class _C {
  static const bg = Color(0xFF121318);
  static const surface = Color(0xFF1E1F25);
  static const surfaceHigh = Color(0xFF292A2F);
  static const text = Color(0xFFE3E1E9);
  static const muted = Color(0xFFC5C9AC);
  static const primary = Color(0xFFD4FF00);
  static const darkOnAccent = Color(0xFF0C0D12);
}

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  static const _wide = 600.0;

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  int _token = 0;

  Future<void> _compose(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _C.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _C.primary),
              title: const Text('Camera', style: TextStyle(color: _C.text)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: _C.primary),
              title: const Text('Photo library',
                  style: TextStyle(color: _C.text)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields, color: _C.primary),
              title: const Text('Text status',
                  style: TextStyle(color: _C.text)),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || source == null) return;
    context.push('/status/new?source=$source');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > StatusScreen._wide;
      return Scaffold(
        backgroundColor: _C.bg,
        appBar: AppBar(
          leading: wide
              ? IconButton(
                  tooltip: 'Chats',
                  icon: const Icon(Icons.forum_outlined),
                  onPressed: () => context.go('/conversations'),
                )
              : null,
          title: const Text('Status',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: _C.primary,
          foregroundColor: _C.darkOnAccent,
          tooltip: 'New status',
          onPressed: () => _compose(context),
          child: const Icon(Icons.camera_alt_outlined),
        ),
        bottomNavigationBar: wide ? null : const HomeNavBar(index: 1),
        body: StreamBuilder<List<StatusPost>>(
          key: ValueKey(_token),
          stream: Supa.watchStatuses(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const AppLoader();
            }
            if (snapshot.hasError) {
              return AppErrorState(
                title: "Statuses didn't load",
                detail: friendlyErrorMessage(snapshot.error,
                    fallback:
                        'Give it another try — updates usually come right back.'),
                onRetry: () => setState(() => _token++),
              );
            }
            final me = Supa.currentUser?.id ?? '';
            final threads = groupStatusFeed(snapshot.data ?? [], me);
            StatusThread? mine;
            for (final thread in threads) {
              if (thread.userId == me) {
                mine = thread;
                break;
              }
            }
            final others = threads.where((t) => t.userId != me).toList();
            return RefreshIndicator(
              color: _C.primary,
              backgroundColor: _C.surface,
              onRefresh: () async {
                // Stream already live; a short delay lets the indicator finish.
                await Future<void>.delayed(const Duration(milliseconds: 400));
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                children: [
                  _MyStatusTile(thread: mine),
                  if (others.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(28, 48, 28, 24),
                      child: Column(
                        children: [
                          Icon(Icons.slow_motion_video_outlined,
                              color: _C.muted, size: 48),
                          SizedBox(height: 14),
                          Text('No updates yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _C.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text(
                            'When contacts share a photo or a thought, it shows up here for 24 hours.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _C.muted, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Text('Recent updates',
                          style: TextStyle(
                              color: _C.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4)),
                    ),
                    ...others.map((thread) => _PeerStatusTile(
                          thread: thread,
                          userIds: others.map((t) => t.userId).toList(),
                        )),
                  ],
                ],
              ),
            );
          },
        ),
      );
    });
  }
}

class _MyStatusTile extends StatelessWidget {
  const _MyStatusTile({this.thread});
  final StatusThread? thread;

  @override
  Widget build(BuildContext context) {
    final post = thread?.latest;
    final has = thread != null && thread!.count > 0;
    return ListTile(
      onTap: has
          ? () => context.push('/status/view/${Supa.currentUser!.id}')
          : () => context.push('/status/new'),
      leading: StatusRingAvatar(
        size: 52,
        active: has,
        child: _MiniAvatar(
          name: post?.userInitial ?? 'Me',
          url: post?.userAvatarUrl,
          size: 52,
        ),
      ),
      title: const Text('My status',
          style: TextStyle(color: _C.text, fontWeight: FontWeight.w700)),
      subtitle: Text(
        has
            ? '${thread!.count} update${thread!.count == 1 ? '' : 's'} · ${statusTimeAgo(post!.createdAt, DateTime.now())} · ${statusTimeLeft(post.expiresAt, DateTime.now())}'
            : 'Tap to share a photo or a thought',
        style: const TextStyle(color: _C.muted, fontSize: 13),
      ),
      trailing: IconButton(
        tooltip: 'New status',
        onPressed: () => context.push('/status/new?source=text'),
        icon: const Icon(Icons.add_circle_outline, color: _C.primary),
      ),
    );
  }
}

class _PeerStatusTile extends StatelessWidget {
  const _PeerStatusTile({required this.thread, required this.userIds});
  final StatusThread thread;
  final List<String> userIds;

  @override
  Widget build(BuildContext context) {
    final post = thread.latest;
    return ListTile(
      onTap: () => context.push(
        '/status/view/${thread.userId}',
        extra: userIds,
      ),
      leading: StatusRingAvatar(
        size: 52,
        child: _MiniAvatar(
          name: post.userInitial,
          url: post.userAvatarUrl,
          size: 52,
        ),
      ),
      title: Text(post.userLabel,
          style: const TextStyle(color: _C.text, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${statusTimeAgo(post.createdAt, DateTime.now())} · ${statusPrivacyLabel(post.privacy)}',
        style: const TextStyle(color: _C.muted, fontSize: 13),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.name, this.url, required this.size});
  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _C.surfaceHigh,
        shape: BoxShape.circle,
      ),
      child: url == null || url!.isEmpty
          ? Text(name.toUpperCase(),
              style: TextStyle(
                  color: _C.text,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700))
          : ClipOval(
              child: Image.network(url!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(name.toUpperCase(),
                          style: TextStyle(
                              color: _C.text,
                              fontSize: size * 0.36,
                              fontWeight: FontWeight.w700))))),
    );
  }
}
