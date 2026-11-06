import 'dart:async';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../ui/states.dart';
import '../services/supabase.dart';
import '../services/status_service.dart';
import '../theme.dart' as theme;

/// Palette from shared theme.dart.
class _SP {
  static const bg = theme.bg;
  static const surface = theme.surface;
  static const surfaceHigh = theme.surfaceHigh;
  static const surfaceLow = theme.surfaceLow;
  static const border = theme.border;
  static const text = theme.text;
  static const muted = theme.muted;
  static const primary = theme.primary;
  static const darkOnAccent = theme.darkOnPrimary;
}

/// Status screen showing personal and contacts' status updates.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  StreamSubscription<List<StatusPost>>? _statusSub;
  List<StatusPost> _myStatuses = [];
  List<StatusPost> _contactStatuses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _subscribeStatuses();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _subscribeStatuses() {
    _statusSub = StatusService.watchStatuses().listen((statuses) {
      if (!mounted) return;
      final me = StatusService.client.auth.currentUser!.id;
      final myList = statuses.where((s) => s.userId == me).toList();
      final contacts = statuses.where((s) => s.userId != me).toList();
      myList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      contacts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _myStatuses = myList;
        _contactStatuses = contacts;
        _loading = false;
      });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _createStatus({
    String? content,
    String? mood,
    String privacy = 'contacts',
  }) async {
    try {
      await StatusService.createStatus(
        content: content,
        mood: mood,
        privacy: privacy,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status posted')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post status')),
        );
      }
    }
  }

  Future<void> _deleteStatus(String statusId) async {
    try {
      await StatusService.deleteStatus(statusId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete status')),
        );
      }
    }
  }

  void _showCreateStatusSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateStatusSheet(
        onCreate: _createStatus,
      ),
    );
  }

  void _showStatusViewer(int initialIndex) {
    final allStatuses = [..._myStatuses, ..._contactStatuses];
    if (allStatuses.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, __, ___) => _StatusViewer(
          statuses: allStatuses,
          initialIndex: initialIndex,
          onDelete: _deleteStatus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/bro_logo.png',
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.flash_on, color: _SP.primary, size: 24),
            ),
            const SizedBox(width: 10),
            const Text('Status',
                style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: _SP.primary,
          unselectedLabelColor: _SP.muted,
          indicatorColor: _SP.primary,
          indicatorWeight: 2.5,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: 'My status  ${_myStatuses.length}'),
            Tab(text: 'Updates  ${_contactStatuses.length}'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateStatusSheet,
        backgroundColor: _SP.primary,
        foregroundColor: _SP.darkOnAccent,
        child: const Icon(Icons.add, size: 28),
      ),
      body: _loading
          ? const AppLoader()
          : TabBarView(
              controller: _tabs,
              children: [
                _MyStatusList(
                  statuses: _myStatuses,
                  onCreate: _showCreateStatusSheet,
                  onView: (i) => _showStatusViewer(i),
                  onDelete: _deleteStatus,
                ),
                _ContactStatusList(
                  statuses: _contactStatuses,
                  onView: (i) => _showStatusViewer(_myStatuses.length + i),
                ),
              ],
            ),
    );
  }
}

/// My statuses tab — shows user's own statuses with add action.
class _MyStatusList extends StatelessWidget {
  const _MyStatusList({
    required this.statuses,
    required this.onCreate,
    required this.onView,
    required this.onDelete,
  });
  final List<StatusPost> statuses;
  final VoidCallback onCreate;
  final void Function(int) onView;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) {
      return AppEmptyState(
        icon: Icons.circle_outlined,
        title: 'No status yet',
        subtitle: 'Share what\'s on your mind — text, mood, or a photo.',
        action: FilledButton.tonalIcon(
          onPressed: onCreate,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add status',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // My status card
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _StatusAvatar(
            url: statuses.first.userAvatarUrl,
            name: statuses.first.userDisplayName ?? '',
            size: 56,
            hasUnviewed: false,
            onTap: () => onView(0),
          ),
          title: Text('My status',
              style: const TextStyle(color: _SP.text, fontWeight: FontWeight.w600)),
          subtitle: Text(
              _formatStatusTime(statuses.first.createdAt),
              style: TextStyle(color: _SP.muted, fontSize: 12)),
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: _SP.muted),
            color: _SP.surface,
            onSelected: (value) {
              if (value == 'delete') onDelete(statuses.first.id);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          onTap: () => onView(0),
        ),
        const Divider(height: 1, color: _SP.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Recent updates',
              style: TextStyle(
                  color: _SP.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        // Older my statuses
        ...statuses.skip(1).toList().asMap().entries.map((entry) {
          final i = entry.key + 1;
          final s = entry.value;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: _StatusAvatar(
              url: s.userAvatarUrl,
              name: s.userDisplayName ?? '',
              size: 48,
              hasUnviewed: false,
              onTap: () => onView(i),
            ),
            title: Text(s.content?.isNotEmpty == true ? s.content! : 'Status',
                style: const TextStyle(color: _SP.text, fontWeight: FontWeight.w600)),
            subtitle: Text(
                _formatStatusTime(s.createdAt),
                style: TextStyle(color: _SP.muted, fontSize: 12)),
            trailing: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: _SP.muted),
              color: _SP.surface,
              onSelected: (value) {
                if (value == 'delete') onDelete(s.id);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            onTap: () => onView(i),
          );
        }),
      ],
    );
  }

  static String _formatStatusTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Contact statuses tab — shows friends' statuses with rings.
class _ContactStatusList extends StatelessWidget {
  const _ContactStatusList({
    required this.statuses,
    required this.onView,
  });
  final List<StatusPost> statuses;
  final void Function(int) onView;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline,
        title: 'No updates from contacts',
      );
    }

    // Group by user
    final byUser = <String, List<StatusPost>>{};
    for (final s in statuses) {
      byUser.putIfAbsent(s.userId, () => []).add(s);
    }
    final users = byUser.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      itemBuilder: (_, i) {
        final userId = users[i];
        final userStatuses = byUser[userId]!;
        final first = userStatuses.first;
        final hasUnviewed = userStatuses.any((s) => !s.expiresAt.isBefore(DateTime.now()));
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _StatusAvatar(
            url: first.userAvatarUrl,
            name: first.userDisplayName ?? '',
            size: 56,
            hasUnviewed: hasUnviewed,
            onTap: () => onView(i),
          ),
          title: Text(first.userDisplayName ?? first.userUsername ?? 'Contact',
              style: const TextStyle(color: _SP.text, fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${userStatuses.length} update${userStatuses.length > 1 ? 's' : ''} • ${_formatStatusTime(first.createdAt)}',
              style: TextStyle(color: _SP.muted, fontSize: 12)),
          onTap: () => onView(i),
        );
      },
    );
  }

  static String _formatStatusTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Avatar with status ring indicator.
class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.hasUnviewed,
    required this.onTap,
  });
  final String? url;
  final String name;
  final double size;
  final bool hasUnviewed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_SP.bg, _SP.surfaceHigh],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: url == null || url!.isEmpty
                ? Text(name.trim().isNotEmpty
                        ? name.trim()[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w600))
                : ClipOval(
                    child: Image.network(url!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(name.trim().isNotEmpty
                                    ? name.trim()[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: size * 0.4,
                                    fontWeight: FontWeight.w600))))),
          ),
          if (hasUnviewed)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.35,
                height: size * 0.35,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_SP.primary, Color(0xFFC7EF00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: _SP.bg, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: _SP.primary.withValues(alpha: 0.45),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet for creating a new status.
class _CreateStatusSheet extends StatefulWidget {
  const _CreateStatusSheet({required this.onCreate});
  final Future<void> Function({
    String? content,
    String? mood,
    String privacy,
  }) onCreate;

  @override
  State<_CreateStatusSheet> createState() => _CreateStatusSheetState();
}

class _CreateStatusSheetState extends State<_CreateStatusSheet> {
  final _textCtrl = TextEditingController();
  String _mood = '';
  String _privacy = 'contacts';
  bool _submitting = false;

  static const _moods = ['😀 Happy', '😢 Sad', '😴 Tired', '😎 Cool',
    '🤔 Thinking', '😍 Excited', '😤 Angry', '🥳 Party'];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _textCtrl.text.trim();
    if (content.isEmpty && _mood.isEmpty) return;
    setState(() => _submitting = true);
    await widget.onCreate(
      content: content.isEmpty ? null : content,
      mood: _mood.isEmpty ? null : _mood.split(' ').last,
      privacy: _privacy,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: _SP.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: _SP.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Text('Create status',
                      style: TextStyle(
                          color: _SP.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: _submitting ? null : () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(
                            color: _SP.primary, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _SP.border),
            // Content
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  // Privacy selector
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      initialValue: _privacy,
                      decoration: InputDecoration(
                        labelText: 'Who can see this',
                        labelStyle: TextStyle(color: _SP.muted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: _SP.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      dropdownColor: _SP.surface,
                      style: TextStyle(color: _SP.text),
                      items: const [
                        DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'followers', child: Text('Followers')),
                      ],
                      onChanged: (v) => setState(() => _privacy = v ?? 'contacts'),
                    ),
                  ),
                  // Mood selector
                  Text('Mood (optional)',
                      style: TextStyle(
                          color: _SP.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _moods.map((m) {
                      final isSelected = _mood == m.split(' ').last;
                      return FilterChip(
                        label: Text(m),
                        selected: isSelected,
                        onSelected: (_) =>
                            setState(() => _mood = isSelected ? '' : m.split(' ').last),
                        backgroundColor: _SP.surface,
                        selectedColor: _SP.primary.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: isSelected ? _SP.primary : _SP.text,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        checkmarkColor: _SP.primary,
                        side: BorderSide(
                            color: isSelected ? _SP.primary : _SP.border),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  // Text input
                  TextField(
                    controller: _textCtrl,
                    maxLines: 6,
                    minLines: 3,
                    style: TextStyle(color: _SP.text, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'What\'s on your mind?',
                      hintStyle: TextStyle(color: _SP.muted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: _SP.surface,
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
            // Post button
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _SP.primary,
                    foregroundColor: _SP.darkOnAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _SP.darkOnAccent))
                      : const Text('Post'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen status viewer (story-style).
class _StatusViewer extends StatefulWidget {
  const _StatusViewer({
    required this.statuses,
    required this.initialIndex,
    required this.onDelete,
  });
  final List<StatusPost> statuses;
  final int initialIndex;
  final void Function(String) onDelete;

  @override
  State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pageCtrl;
  late final AnimationController _progressCtrl;
  late Animation<double> _progressAnim;
  Timer? _advanceTimer;
  int _currentIndex = 0;
  bool _paused = false;
  bool _exiting = false;

  static const _storyDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.statuses.length - 1);
    _pageCtrl = PageController(initialPage: _currentIndex);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: _storyDuration,
    );
    _progressAnim = Tween(begin: 0.0, end: 1.0).animate(_progressCtrl)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_paused) {
          _advance();
        }
      });
    _startStory();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _pageCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _startStory() {
    _progressCtrl.reset();
    if (!_paused) _progressCtrl.forward();
  }

  void _advance() {
    if (_currentIndex < widget.statuses.length - 1) {
      _currentIndex++;
      _pageCtrl.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      _startStory();
    } else if (!_exiting) {
      _exiting = true;
      Navigator.pop(context);
    }
  }

  void _previous() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _pageCtrl.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
    _startStory();
  }

  void _handleTap(TapDownDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    if (details.globalPosition.dx < width / 3) {
      _previous();
    } else {
      _advance();
    }
  }

  void _handleLongPressStart(LongPressStartDetails _) => setState(() {
    _paused = true;
    _progressCtrl.stop();
  });

  void _handleLongPressEnd(LongPressEndDetails _) => setState(() {
    _paused = false;
    _startStory();
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTap,
      onLongPressStart: _handleLongPressStart,
      onLongPressEnd: _handleLongPressEnd,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.statuses.length,
              itemBuilder: (_, i) => _StatusStoryPage(
                status: widget.statuses[i],
                isCurrent: i == _currentIndex,
              ),
            ),
            // Progress bars at top
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 12,
              right: 12,
              child: Row(
                children: List.generate(widget.statuses.length, (i) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i < widget.statuses.length - 1 ? 4 : 0),
                      child: _SProgressBar(
                        progress: i < _currentIndex
                            ? 1.0
                            : (i == _currentIndex ? _progressAnim.value : null),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // User info at top
            Positioned(
              top: MediaQuery.paddingOf(context).top + 44,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _Avatar(
                    name: widget.statuses[_currentIndex].userDisplayName ?? '',
                    url: widget.statuses[_currentIndex].userAvatarUrl,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            widget.statuses[_currentIndex].userDisplayName ??
                                widget.statuses[_currentIndex].userUsername ??
                                'Contact',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        Text(
                            _formatTime(widget.statuses[_currentIndex].createdAt),
                            style: TextStyle(
                                color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (widget.statuses[_currentIndex].userId == StatusService.client.auth.currentUser!.id)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: Colors.white),
                      color: _SP.surface,
                      onSelected: (value) {
                        if (value == 'delete') {
                          widget.onDelete(widget.statuses[_currentIndex].id);
                          if (_currentIndex >= widget.statuses.length - 1) {
                            Navigator.pop(context);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                ],
              ),
            ),
            // Content at bottom
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: _StatusContent(status: widget.statuses[_currentIndex]),
            ),
            // Swipe down hint
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Swipe down to exit',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Progress bar for each story segment.
class _SProgressBar extends StatelessWidget {
  const _SProgressBar({this.progress});
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(1.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress ?? 0.0,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_SP.primary, const Color(0xFFC7EF00)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ),
    );
  }
}

/// Local avatar widget (mirrors main.dart _Avatar for status screen use).
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    this.size = 44,
    this.url,
  });
  final String name;
  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_SP.bg, _SP.surfaceHigh],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: url == null || url!.isEmpty
          ? Text(name.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600))
          : ClipOval(
              child: Image.network(url!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(name.toUpperCase(),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: size * 0.4,
                              fontWeight: FontWeight.w600))))),
    );
    return avatar;
  }
}

/// Story page content.
class _StatusStoryPage extends StatelessWidget {
  const _StatusStoryPage({required this.status, required this.isCurrent});
  final StatusPost status;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (status.mediaPath != null)
          FutureBuilder<String>(
            future: StatusService.client.storage.from('attachments').getPublicUrl(status.mediaPath!),
            builder: (_, snap) {
              if (snap.hasData) {
                return Image.network(snap.data!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.white54)));
              }
              return const Center(child: CircularProgressIndicator());
            },
          )
        else
          Container(
            color: _SP.surfaceLow,
          ),
        // Gradient overlay for text readability
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.7),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Status content overlay at bottom.
class _StatusContent extends StatelessWidget {
  const _StatusContent({required this.status});
  final StatusPost status;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    if (status.content != null && status.content!.isNotEmpty) {
      parts.add(Text(status.content!,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, height: 1.4),
          textAlign: TextAlign.center));
    }
    if (status.mood != null && status.mood!.isNotEmpty) {
      if (parts.isNotEmpty) parts.add(const SizedBox(height: 10));
      parts.add(Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mood, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(status.mood!,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ));
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: parts,
    );
  }
}