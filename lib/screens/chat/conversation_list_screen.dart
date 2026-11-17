import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/presence.dart';
import '../../models/profile.dart';
import '../../ui/states.dart';
import '../navigation/nav_sidebar.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;
import 'widgets/avatar.dart';
import '../../widgets/status_ring_avatar.dart';
import '../../widgets/home_nav_bar.dart';
import '../../services/push_notifications.dart';
import '../../ui/motion.dart';

const _adaptiveBreakpoint = app_colors.adaptiveBreakpoint;

class _P {
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const primary = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message, this.detail, required this.onRetry});
  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: _P.muted, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _P.text, fontSize: 16, fontWeight: FontWeight.w600)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _P.muted, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}




String _formatConversationTimestamp(DateTime dt) {
  final now = DateTime.now();
  final local = dt.toLocal();
  if (now.year == local.year) {
    return DateFormat('MMM d').format(local);
  }
  return DateFormat('MM/dd/yy').format(local);
}

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});
  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  int _conversationsTick = 0;
  StreamSubscription<List<StatusPost>>? _statusSub;
  Set<String> _statusUserIds = {};

  Future<List<Profile>>? _suggestions;
  List<Profile> _searchResults = [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searchLoading = false;
  bool _searchCompleted = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _suggestions = Supa.searchUsers('').catchError((e) {
      debugPrint('Failed to load chat suggestions: $e');
      return <Profile>[];
    });
    _statusSub = Supa.watchStatuses().listen((posts) {
      if (!mounted) return;
      setState(() => _statusUserIds = {for (final p in posts) p.userId});
    }, onError: (_) {});
  }

  void _reloadSuggestions() {
    if (mounted) setState(() => _suggestions = Supa.searchUsers(''));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final requestId = ++_searchRequestId;
    final query = value.trim();
    setState(() {
      _searchResults = [];
      _searchError = null;
      _searchLoading = false;
      _searchCompleted = false;
    });
    if (query.isEmpty) return;

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchLoading = true);
      try {
        final results = await Supa.searchUsers(query);
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchResults = results;
          _searchLoading = false;
          _searchCompleted = true;
        });
      } catch (e) {
        debugPrint('Search failed: $e');
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchError =
              "We couldn't search just now. Check your connection and try again.";
          _searchLoading = false;
          _searchCompleted = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchRequestId++;
    _statusSub?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Widget _conversationAvatar(BuildContext context, Conversation conv) {
    final hasStatus =
        conv.peerId != null && _statusUserIds.contains(conv.peerId);
    final avatar = ValueListenableBuilder<int>(
      valueListenable: Presence.epoch,
      builder: (_, __, ___) => Avatar(
        name: conv.peerInitial,
        url: conv.peerAvatarUrl,
        size: 46,
        showOnlineDot: Presence.isOnline(conv.peerId),
      ),
    );
    if (hasStatus) {
      return StatusRingAvatar(
        size: 46,
        onTap: () => context.push('/status/view/${conv.peerId}'),
        child: avatar,
      );
    }
    return GestureDetector(
      onTap: conv.peerId != null
          ? () => context.push('/profile/${conv.peerId}')
          : null,
      child: avatar,
    );
  }

  Future<void> _startDM(Profile other) async {
    try {
      final conv = await Supa.getOrCreateDM(other.id);
      if (mounted) context.go('/chat/${conv.id}', extra: other);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("We couldn't open that chat. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > _adaptiveBreakpoint;
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
                      const Icon(Icons.flash_on, color: _P.primary, size: 24),
                ),
                const SizedBox(width: 10),
                const Text('BRO',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ],
            ),
            actions: [
              IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () => context.push('/settings')),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
                onPressed: () async {
                  await PushNotifications.unregisterCurrentToken();
                  await Supa.signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
          body: wide
              ? _buildLargeScreenLayout(context)
              : _buildSmallScreenLayout(context),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _P.primary,
            foregroundColor: _P.darkOnAccent,
            tooltip: 'New message',
            elevation: 4,
            onPressed: () => _searchFocusNode.requestFocus(),
            child: const Icon(Icons.edit_outlined, size: 22),
          ),
          bottomNavigationBar: wide ? null : const HomeNavBar(index: 0),
        );
      },
    );
  }

  Widget _buildSmallScreenLayout(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: _P.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _searchFocusNode.hasFocus
                    ? _P.primary.withValues(alpha: 0.6)
                    : _P.border.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _search,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: _P.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search people or username...',
                hintStyle: TextStyle(
                    color: _P.muted.withValues(alpha: 0.7), fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: _P.primary, size: 22),
                filled: false,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: _P.muted, size: 20),
                        onPressed: () {
                          _search.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ),
        if (_search.text.trim().isNotEmpty && _searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              minHeight: 2,
              color: _P.primary,
              backgroundColor: _P.surfaceHigh,
            ),
          ),
        if (_search.text.trim().isNotEmpty && _searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_searchError!,
                style: const TextStyle(color: _P.muted, height: 1.35)),
          ),
        if (_search.text.trim().isNotEmpty &&
            _searchCompleted &&
            _searchError == null &&
            _searchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No users found.', style: TextStyle(color: _P.muted)),
          ),
        if (_search.text.trim().isNotEmpty && _searchResults.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Users',
                style: TextStyle(
                    color: _P.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            height: (_searchResults.length * 72.0).clamp(72.0, 288.0),
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final u = _searchResults[index];
                return ListTile(
                  leading: GestureDetector(
                    onTap: () => context.push('/profile/${u.id}'),
                    child: Avatar(
                        name: u.peerInitial, url: u.avatarUrl, size: 44),
                  ),
                  title: Text(u.label, style: const TextStyle(color: _P.text)),
                  subtitle: Text('@${u.username}',
                      style: TextStyle(color: _P.muted, fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_outline, size: 20),
                    color: _P.muted,
                    tooltip: 'View profile',
                    onPressed: () => context.push('/profile/${u.id}'),
                  ),
                  onTap: () => _startDM(u),
                );
              },
            ),
          ),
          const Divider(height: 1),
        ],
        if (_search.text.trim().isEmpty)
          FutureBuilder<List<Profile>>(
            future: _suggestions,
            builder: (context, snapshot) {
              final people = snapshot.data ?? const <Profile>[];
              if (people.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: Text(
                        'People you may know',
                        style: TextStyle(
                          color: _P.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (int idx = 0; idx < people.take(8).length; idx++)
                            FadeSlideIn(
                              index: idx,
                              offset: const Offset(0.08, 0),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: PressScale(
                                  scaleFactor: 0.94,
                                  onTap: () => _startDM(people[idx]),
                                  onLongPress: () =>
                                      context.push('/profile/${people[idx].id}'),
                                  child: SizedBox(
                                    width: 76,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _P.primary.withValues(alpha: 0.35),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Avatar(
                                            name: people[idx].peerInitial,
                                            url: people[idx].avatarUrl,
                                            size: 44,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '@${people[idx].username}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: _P.text,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Chats',
                  style: TextStyle(
                      color: _P.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              StreamBuilder<AuthState>(
                stream: Supa.authStateChanges,
                builder: (_, __) => Text(Supa.currentUser?.email ?? '',
                    style: TextStyle(color: _P.muted, fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            key: _refreshKey,
            onRefresh: _onRefresh,
            color: _P.primary,
            backgroundColor: _P.primary.withValues(alpha: 0.12),
            child: StreamBuilder<List<Conversation>>(
              key: ValueKey(_conversationsTick),
              stream: Supa.watchConversations(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const ListSkeleton(label: 'Loading chats');
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                      message: "Your chats didn't load",
                      detail:
                          'Give it another try — they usually come right back.',
                      onRetry: () => setState(() => _conversationsTick++));
                }
                final conversations = snapshot.data ?? [];
                Presence.setListPeers(conversations.map((c) => c.peerId));
                if (conversations.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: _P.surfaceHigh,
                              shape: BoxShape.circle,
                              border: Border.all(color: _P.border),
                            ),
                            child: const Center(
                              child: Icon(Icons.forum_outlined,
                                  color: _P.primary, size: 36),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text('No chats yet',
                              style: TextStyle(
                                  color: _P.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text(
                              'Search for users or pick from suggestions above to start messaging.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: _P.muted, fontSize: 13, height: 1.4)),
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: () => _searchFocusNode.requestFocus(),
                            style: FilledButton.styleFrom(
                              backgroundColor: _P.surface,
                              foregroundColor: _P.primary,
                            ),
                            icon: const Icon(Icons.person_search_outlined,
                                size: 18),
                            label: const Text('Find someone',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: conversations.length,
                      itemBuilder: (_, i) {
                        final conv = conversations[i];
                        final lastMessage = conv.lastMessage;
                        final lastMessageAt = conv.lastMessageAt;
                        final unread = conv.unreadCount > 0;
                        return FadeSlideIn(
                          key: ValueKey(conv.id),
                          index: i.clamp(0, 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            child: PressScale(
                              scaleFactor: 0.98,
                              child: ListTile(
                                leading: _conversationAvatar(context, conv),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        conv.peerLabel,
                                        style: TextStyle(
                                          color: _P.text,
                                          fontWeight: unread
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (lastMessageAt != null)
                                      Text(
                                        _formatConversationTimestamp(lastMessageAt),
                                        style: TextStyle(
                                          color: unread ? _P.primary : _P.muted,
                                          fontWeight: unread
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (conv.peerUsername != null &&
                                        lastMessage == null)
                                      Text(
                                        '@${conv.peerUsername}',
                                        style: TextStyle(
                                          color: _P.muted.withValues(alpha: 0.8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    if (lastMessage != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          lastMessage.startsWith('attachment:')
                                              ? '📎 Attachment'
                                              : (lastMessage.startsWith('voice:')
                                                  ? '🎤 Voice note'
                                                  : lastMessage),
                                          style: TextStyle(
                                            color: unread ? _P.text : _P.muted,
                                            fontWeight: unread
                                                ? FontWeight.w500
                                                : FontWeight.normal,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (conv.isLocked)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Icon(Icons.lock_outline_rounded,
                                            size: 15, color: _P.muted),
                                      ),
                                    if (unread)
                                      PulseScale(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          constraints: const BoxConstraints(
                                              minWidth: 20, minHeight: 20),
                                          decoration: BoxDecoration(
                                            color: _P.primary,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            boxShadow: [
                                              BoxShadow(
                                                color: _P.primary
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 8,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: Text(
                                            conv.unreadCount > 99
                                                ? '99+'
                                                : '${conv.unreadCount}',
                                            style: const TextStyle(
                                                color: _P.darkOnAccent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                tileColor: unread
                                    ? _P.primary.withValues(alpha: 0.04)
                                    : Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                onTap: () => context.go('/chat/${conv.id}',
                                    extra: conv.toPeerProfile()),
                                onLongPress: conv.peerId != null
                                    ? () =>
                                        context.push('/profile/${conv.peerId}')
                                    : null,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onRefresh() async {
    if (mounted) setState(() => _conversationsTick++);
    _reloadSuggestions();
  }

  Widget _buildLargeScreenLayout(BuildContext context) {
    return Row(
      children: [
        const NavSidebar(),
        Expanded(
          child: _buildSmallScreenLayout(context),
        ),
      ],
    );
  }
}

