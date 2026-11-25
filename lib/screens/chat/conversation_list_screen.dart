import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../ui/errors.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/search_safety.dart';
import '../../services/supabase.dart';
import '../../services/people_search_history.dart';
import '../../services/presence.dart';
import '../../models/profile.dart';
import '../../ui/states.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;
import 'widgets/avatar.dart';
import '../../widgets/status_ring_avatar.dart';
import '../../widgets/responsive_app_shell.dart';
import '../../widgets/recent_people_searches.dart';
import '../../services/push_notifications.dart';
import '../../ui/motion.dart';
import '../../widgets/search_highlight.dart';

class _P {
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const primary = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
  static const success = app_colors.success;
  static const bg = app_colors.bg;
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

class _MessageRequestTile extends StatelessWidget {
  const _MessageRequestTile({
    required this.request,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
  });

  final Map<String, dynamic> request;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final name = (request['peer_display_name'] as String?)?.trim();
    final username = (request['peer_username'] as String?)?.trim();
    final label = name?.isNotEmpty == true
        ? name!
        : (username?.isNotEmpty == true ? '@$username' : 'New contact');
    final avatarUrl = request['peer_avatar_url'] as String?;
    final initial = label.replaceFirst('@', '').trim();
    return ListTile(
      onTap: onOpen,
      leading: Avatar(
        name: initial.isEmpty ? '?' : initial[0].toUpperCase(),
        url: avatarUrl,
        size: 42,
      ),
      title: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _P.text, fontWeight: FontWeight.w600)),
      subtitle: Text(
        (request['last_message'] as String?)?.trim().isNotEmpty == true
            ? request['last_message'] as String
            : 'Wants to start a conversation',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _P.muted, fontSize: 12),
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Decline',
            onPressed: () => onDecline(),
            icon: const Icon(Icons.close, color: _P.muted, size: 20),
          ),
          IconButton(
            tooltip: 'Accept',
            onPressed: () => onAccept(),
            icon: const Icon(Icons.check_circle_outline,
                color: _P.primary, size: 22),
          ),
        ],
      ),
    );
  }
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  late Stream<List<Conversation>> _conversations = Supa.watchConversations();
  StreamSubscription<List<StatusPost>>? _statusSub;
  Set<String> _statusUserIds = {};

  Future<List<FriendSuggestion>>? _suggestions;
  List<Profile> _searchResults = [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searchLoading = false;
  bool _searchCompleted = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _suggestions = Supa.getFriendSuggestions(limit: 8).catchError((e) {
      debugPrint('Failed to load chat suggestions: $e');
      return <FriendSuggestion>[];
    });
    _statusSub = Supa.watchStatuses().listen((posts) {
      if (!mounted) return;
      setState(() => _statusUserIds = {for (final p in posts) p.userId});
    }, onError: (_) {});
  }

  void _reloadSuggestions() {
    if (mounted) {
      setState(() => _suggestions = Supa.getFriendSuggestions(limit: 8));
    }
  }

  void _onSearchChanged(String value, {bool immediate = false}) {
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

    final delay = immediate ? Duration.zero : const Duration(milliseconds: 300);
    _searchDebounce = Timer(delay, () async {
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
          _searchError = kLoadFailedDetail;
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
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  String? _searchAccountId() => Supa.currentUser?.id;

  void _onSearchFocusChanged() => setState(() {});

  void _rememberSearch(String value) {
    unawaited(PeopleSearchHistory.remember(_searchAccountId(), value));
  }

  void _selectRecentSearch(String value) {
    _search.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _searchFocusNode.requestFocus();
    _rememberSearch(value);
    _onSearchChanged(value, immediate: true);
  }

  void _clearSearch() {
    _search.clear();
    _onSearchChanged('');
    _searchFocusNode.requestFocus();
  }

  void _onSearchResultTap(Profile user) {
    _rememberSearch(_search.text);
    FocusScope.of(context).unfocus();
    _startDM(user.id);
  }

  Future<void> _startDM(String peerId) async {
    try {
      final conv = await Supa.getOrCreateDM(peerId);
      if (mounted) context.go('/chat/${conv.id}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("We couldn't open that chat. Please try again.")),
      );
    }
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

  Widget _messageRequestsSection(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supa.watchMessageRequests(),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? const <Map<String, dynamic>>[];
        if (requests.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _P.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _P.primary.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Text('Message requests',
                      style: TextStyle(
                          color: _P.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                for (final request in requests.take(5))
                  _MessageRequestTile(
                    request: request,
                    onAccept: () async {
                      final conversationId =
                          request['conversation_id'] as String?;
                      final peerId = request['peer_id'] as String?;
                      if (conversationId == null || peerId == null) return;
                      await Supa.acceptMessageRequest(conversationId, peerId);
                      _reloadConversations();
                    },
                    onDecline: () async {
                      final conversationId =
                          request['conversation_id'] as String?;
                      if (conversationId == null) return;
                      await Supa.declineMessageRequest(conversationId);
                      _reloadConversations();
                    },
                    onOpen: () {
                      final conversationId =
                          request['conversation_id'] as String?;
                      if (conversationId != null) {
                        context.go('/chat/$conversationId');
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _signOut() async {
    await PushNotifications.unregisterCurrentToken();
    await Supa.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: 'Chats',
      subtitle: 'Your conversations and new contacts',
      navIndex: 0,
      body: _buildSmallScreenLayout(context),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Sign out',
          onPressed: _signOut,
        ),
      ],
      floatingActionButton: FloatingActionButton(
        backgroundColor: _P.primary,
        foregroundColor: _P.darkOnAccent,
        tooltip: 'New message',
        elevation: 4,
        onPressed: () => _searchFocusNode.requestFocus(),
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
    );
  }

  Widget _buildPeopleSearchResults() {
    if (_searchLoading) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [_searchSkeleton()],
      );
    }
    if (_searchError != null) {
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        children: [
          _searchErrorWidget(
            message: _searchError!,
            onRetry: () => _onSearchChanged(_search.text),
          ),
        ],
      );
    }
    if (_searchCompleted && _searchResults.isEmpty) {
      return ListView(
        shrinkWrap: true,
        children: [
          _searchEmptyState(query: _search.text.trim(), onClear: _clearSearch),
        ],
      );
    }
    if (_searchResults.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      key: const ValueKey('chats-people-search-results'),
      shrinkWrap: true,
      itemCount: _searchResults.length + 1,
      padding: const EdgeInsets.only(bottom: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text('People',
                style: TextStyle(
                  color: _P.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                )),
          );
        }
        final user = _searchResults[index - 1];
        return FadeSlideIn(
          key: ValueKey(user.id),
          index: (index - 1).clamp(0, 7),
          child: _searchResultTile(
            user: user,
            query: sanitizeSearchTerm(_search.text),
            isOnline: Presence.isOnline(user.id),
            onTap: () => _onSearchResultTap(user),
            onProfileTap: () {
              _rememberSearch(_search.text);
              context.push('/profile/${user.id}');
            },
          ),
        );
      },
    );
  }

  Widget _buildSmallScreenLayout(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
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
                hintText: 'Search people or @username...',
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
                        onPressed: _clearSearch,
                        tooltip: 'Clear search',
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _rememberSearch,
              onChanged: _onSearchChanged,
              onTapOutside: (_) => _searchFocusNode.unfocus(),
            ),
          ),
        ),
        RecentPeopleSearches(
          controller: _search,
          focusNode: _searchFocusNode,
          accountId: _searchAccountId,
          onSelected: _selectRecentSearch,
        ),
        if (_search.text.trim().isNotEmpty)
          Flexible(flex: 2, child: _buildPeopleSearchResults()),
        if (_search.text.trim().isEmpty && !_searchFocusNode.hasFocus)
          FutureBuilder<List<FriendSuggestion>>(
            future: _suggestions,
            builder: (context, snapshot) {
              final people = snapshot.data ?? const <FriendSuggestion>[];
              if (people.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 136,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: Row(
                        children: [
                          Text(
                            'People you may know',
                            style: TextStyle(
                              color: _P.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.psychology_outlined,
                              size: 13, color: _P.muted.withValues(alpha: 0.6)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => context.push('/suggest-friends'),
                            icon: Icon(Icons.chevron_right,
                                size: 16, color: _P.primary),
                            label: Text('See all',
                                style: TextStyle(
                                  color: _P.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                )),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          for (int idx = 0; idx < people.take(8).length; idx++)
                            FadeSlideIn(
                              index: idx,
                              offset: const Offset(0.08, 0),
                              child: _suggestionTile(
                                user: people[idx],
                                onTap: () => _startDM(people[idx].userId),
                                onLongPress: () => context
                                    .push('/profile/${people[idx].userId}'),
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
        if (_search.text.trim().isEmpty && !_searchFocusNode.hasFocus)
          _messageRequestsSection(context),
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
              stream: _conversations,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const ListSkeleton(label: 'Loading chats');
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                      message: "Your chats didn't load",
                      detail: kLoadFailedDetail,
                      onRetry: _reloadConversations);
                }
                final allConversations =
                    Supa.sortConversationsByRecent(snapshot.data ?? []);
                Presence.setListPeers(allConversations.map((c) => c.peerId));
                final rawQuery = _search.text.trim();
                final normalizedQuery = sanitizeSearchTerm(rawQuery);
                final filterQuery = normalizedQuery.toLowerCase();
                final conversations = rawQuery.isEmpty
                    ? allConversations
                    : filterQuery.isEmpty
                        ? <Conversation>[]
                        : allConversations.where((c) {
                            final name = c.peerLabel.toLowerCase();
                            final username = c.peerUsername?.toLowerCase();
                            return name.contains(filterQuery) ||
                                (username?.contains(filterQuery) ?? false);
                          }).toList();
                if (conversations.isEmpty && allConversations.isNotEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              color: _P.muted, size: 40),
                          const SizedBox(height: 14),
                          Text(
                            'No chats match\n"${_search.text.trim()}"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: _P.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.4),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Try searching by username above to find them.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _P.muted, fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (allConversations.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
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
                    constraints: const BoxConstraints(maxWidth: 720),
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
                                      child: SearchHighlightText(
                                        text: conv.peerLabel,
                                        query: normalizedQuery,
                                        style: TextStyle(
                                          color: _P.text,
                                          fontWeight: unread
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                        highlightStyle: const TextStyle(
                                          color: _P.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (lastMessageAt != null)
                                      Text(
                                        _formatConversationTimestamp(
                                            lastMessageAt),
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
                                    ValueListenableBuilder<int>(
                                      valueListenable: Presence.epoch,
                                      builder: (_, __, ___) {
                                        final game = Presence.game(conv.peerId);
                                        final label = game?.playingLabel;
                                        if (label == null) {
                                          return const SizedBox.shrink();
                                        }
                                        return Text(
                                          label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _P.primary
                                                .withValues(alpha: 0.9),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        );
                                      },
                                    ),
                                    if (conv.peerUsername != null &&
                                        lastMessage == null)
                                      Text(
                                        '@${conv.peerUsername}',
                                        style: TextStyle(
                                          color:
                                              _P.muted.withValues(alpha: 0.8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    if (lastMessage != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          lastMessage.startsWith('attachment:')
                                              ? '📎 Attachment'
                                              : (lastMessage
                                                      .startsWith('voice:')
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
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
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
        ),
      ),
    );
  }

  void _reloadConversations() {
    if (mounted) setState(() => _conversations = Supa.watchConversations());
  }

  Future<void> _onRefresh() async {
    _reloadConversations();
    _reloadSuggestions();
  }

  // ===== Search UI Components =====

  /// Skeleton loader for search results.
  Widget _searchSkeleton() {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.onSurface.withValues(alpha: 0.08);
    return Column(
      children: List.generate(4, (index) {
        return Shimmer(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration:
                      BoxDecoration(color: block, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: block,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 100,
                        height: 12,
                        decoration: BoxDecoration(
                          color: block,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  /// Error state for search.
  Widget _searchErrorWidget(
      {required String message, required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _P.muted.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _P.muted.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: _P.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: _P.muted, fontSize: 13, height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: _P.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            child: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Empty state for search results.
  Widget _searchEmptyState(
      {required String query, required VoidCallback onClear}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _P.surfaceHigh,
              shape: BoxShape.circle,
              border: Border.all(color: _P.border.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.person_search_rounded, color: _P.muted, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            'No results for "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _P.text,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different name or @username',
            textAlign: TextAlign.center,
            style: TextStyle(color: _P.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded, size: 18),
            label: const Text('Clear search',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _P.primary,
              side: BorderSide(color: _P.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }

  /// Individual search result tile.
  Widget _searchResultTile({
    required Profile user,
    required String query,
    required bool isOnline,
    required VoidCallback onTap,
    required VoidCallback onProfileTap,
  }) {
    return PressScale(
      scaleFactor: 0.98,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _P.border.withValues(alpha: 0.25)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Avatar with online indicator
                  GestureDetector(
                    onTap: onProfileTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Avatar(
                          name: user.peerInitial,
                          url: user.avatarUrl,
                          size: 48,
                        ),
                        if (isOnline)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: _P.success,
                                shape: BoxShape.circle,
                                border: Border.all(color: _P.bg, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: _P.success.withValues(alpha: 0.4),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name and username
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SearchHighlightText(
                          text: user.label,
                          query: query,
                          style: const TextStyle(
                            color: _P.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 15.5,
                          ),
                          highlightStyle: const TextStyle(
                            color: _P.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        SearchHighlightText(
                          text: '@${user.username}',
                          query: query,
                          style: TextStyle(color: _P.muted, fontSize: 12.5),
                          highlightStyle: TextStyle(
                            color: _P.primary.withValues(alpha: 0.85),
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Message button
                  PressScale(
                    scaleFactor: 0.92,
                    onTap: onTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _P.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _P.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 16, color: _P.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'Message',
                            style: TextStyle(
                              color: _P.primary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Suggestion tile for 'People you may know' section.
  Widget _suggestionTile({
    required FriendSuggestion user,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final isOnline = user.isOnline;
    return PressScale(
      scaleFactor: 0.94,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 78,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _P.primary.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Avatar(
                    name: user.peerInitial,
                    url: user.avatarUrl,
                    size: 46,
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _P.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: _P.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '@${user.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _P.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
