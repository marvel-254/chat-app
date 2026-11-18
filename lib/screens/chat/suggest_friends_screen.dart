import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/people_search_history.dart';
import '../../services/presence.dart';
import '../../models/profile.dart';
import '../../ui/states.dart';
import '../../ui/motion.dart';
import 'widgets/avatar.dart';
import '../../widgets/responsive_app_shell.dart';
import '../../widgets/recent_people_searches.dart';

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

class SuggestFriendsScreen extends StatefulWidget {
  const SuggestFriendsScreen({
    super.key,
    this.loadSuggestions = _defaultLoadSuggestions,
    this.searchUsers = Supa.searchUsers,
    this.getFollowedUserIds = Supa.getFollowedUserIds,
    this.setFollowing = Supa.setFollowing,
    this.recentSearchAccountId = _currentAccountId,
  });

  final Future<List<FriendSuggestion>> Function(String category) loadSuggestions;
  final Future<List<Profile>> Function(String query) searchUsers;
  final Future<Set<String>> Function(List<String> userIds) getFollowedUserIds;
  final Future<void> Function(String userId, bool follow) setFollowing;
  final String? Function() recentSearchAccountId;

  static String? _currentAccountId() => Supa.currentUser?.id;

  static Future<List<FriendSuggestion>> _defaultLoadSuggestions(
    String category,
  ) =>
      Supa.getFriendSuggestionsByCategory(category, limit: 20);

  @override
  State<SuggestFriendsScreen> createState() => _SuggestFriendsScreenState();
}

class _SuggestFriendsScreenState extends State<SuggestFriendsScreen> {
  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searchLoading = false;
  List<FriendSuggestion> _searchResults = [];
  bool _searchCompleted = false;
  String? _searchError;
  bool _searchFollowReady = false;
  bool _searchFollowFailed = false;

  // Category tabs
  final _categories = [
    _CategoryTab(id: 'all', label: 'All', icon: Icons.people_outline),
    _CategoryTab(id: 'circles', label: 'From Circles', icon: Icons.group_outlined),
    _CategoryTab(id: 'mutual', label: 'Mutual Connections', icon: Icons.handshake_outlined),
    _CategoryTab(id: 'groups', label: 'Shared Groups', icon: Icons.forum_outlined),
    _CategoryTab(id: 'followers', label: 'Followers', icon: Icons.person_add_alt_1_outlined),
  ];

  int _selectedCategoryIndex = 0;
  final Map<String, List<FriendSuggestion>> _categoryCache = {};
  final Set<String> _loadingCategories = {};
  final Set<String> _failedCategories = {};
  final Set<String> _followInFlight = {};
  final _followChanges = <String, ({bool following, int revision})>{};
  int _followRevision = 0;

  FriendSuggestion _mergeFollowChange(FriendSuggestion user, int since) {
    final change = _followChanges[user.userId];
    return change != null && change.revision > since
        ? user.withFollowing(change.following)
        : user;
  }

  @override
  void initState() {
    super.initState();
    _loadCategory('all');
  }

  Future<void> _loadCategory(String category, {bool refresh = false}) async {
    if (_loadingCategories.contains(category) ||
        (!refresh && _categoryCache.containsKey(category) &&
            !_failedCategories.contains(category))) {
      return;
    }
    setState(() {
      _loadingCategories.add(category);
      _failedCategories.remove(category);
    });
    try {
      final followRevision = _followRevision;
      final results = await widget.loadSuggestions(category);
      if (!mounted) return;
      setState(() => _categoryCache[category] =
          results.map((user) => _mergeFollowChange(user, followRevision)).toList());
    } catch (error) {
      debugPrint('Failed to load category $category: $error');
      if (!mounted) return;
      setState(() => _failedCategories.add(category));
    } finally {
      if (mounted) setState(() => _loadingCategories.remove(category));
    }
  }

  void _onCategoryChanged(int index) {
    setState(() => _selectedCategoryIndex = index);
    final category = _categories[index].id;
    _loadCategory(category);
  }

  void _onSearchChanged(String value, {bool immediate = false}) {
    _searchDebounce?.cancel();
    final requestId = ++_searchRequestId;
    final query = value.trim();
    setState(() {
      _searchResults = [];
      _searchError = null;
      _searchFollowReady = false;
      _searchFollowFailed = false;
      _searchLoading = false;
      _searchCompleted = false;
    });
    if (query.isEmpty) return;

    final delay = immediate ? Duration.zero : const Duration(milliseconds: 300);
    _searchDebounce = Timer(delay, () async {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchLoading = true);
      try {
        final results = await widget.searchUsers(query);
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchResults = results
              .map((u) => FriendSuggestion(
                    userId: u.id,
                    username: u.username,
                    displayName: u.displayName,
                    avatarUrl: u.avatarUrl,
                    lastSeenAt: u.lastSeenAt,
                    isOnline: Presence.isOnline(u.id),
                    mutualCount: 0,
                    suggestionReason: 'Found via search',
                    suggestionType: 'Search',
                    isFollowing: false,
                    isCloseFriend: false,
                  ))
              .toList();
          _searchLoading = false;
          _searchCompleted = true;
        });
        if (results.isNotEmpty) {
          unawaited(_loadSearchFollowStatus(requestId));
        }
      } catch (e) {
        debugPrint('Search failed: $e');
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchError = "We couldn't search just now. Check your connection and try again.";
          _searchLoading = false;
          _searchCompleted = true;
        });
      }
    });
  }

  Future<void> _loadSearchFollowStatus(int requestId) async {
    if (!mounted || requestId != _searchRequestId) return;
    if (_searchFollowFailed) setState(() => _searchFollowFailed = false);
    final revision = _followRevision;
    final ids = _searchResults.map((user) => user.userId).toList();
    try {
      final followedIds = await widget.getFollowedUserIds(ids);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchResults = _searchResults
            .map((user) => _mergeFollowChange(
                  user.withFollowing(followedIds.contains(user.userId)),
                  revision,
                ))
            .toList();
        _searchFollowReady = true;
      });
    } catch (error) {
      debugPrint('Follow status lookup failed: $error');
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchFollowFailed = true);
    }
  }

  void _rememberSearch(String value) {
    unawaited(PeopleSearchHistory.remember(widget.recentSearchAccountId(), value));
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

  Future<void> _startDM(FriendSuggestion user) async {
    try {
      final conv = await Supa.getOrCreateDM(user.userId);
      if (mounted) context.go('/chat/${conv.id}', extra: user.toProfile());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("We couldn't open that chat. Please try again.")),
      );
    }
  }

  Future<void> _toggleFollow(FriendSuggestion user) async {
    if (!_followInFlight.add(user.userId)) return;
    final following = !user.isFollowing;
    try {
      await widget.setFollowing(user.userId, following);
      if (!mounted) return;
      setState(() {
        _followChanges[user.userId] = (
          following: following,
          revision: ++_followRevision,
        );
        List<FriendSuggestion> update(List<FriendSuggestion> users) => users
            .map((item) => item.userId == user.userId
                ? item.withFollowing(following)
                : item)
            .toList();
        _searchResults = update(_searchResults);
        _categoryCache.updateAll((_, suggestions) => update(suggestions));
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update follow status. Try again.")),
      );
    } finally {
      _followInFlight.remove(user.userId);
    }
  }

  Future<void> _toggleCloseFriend(FriendSuggestion user) async {
    try {
      await Supa.setCloseFriend(user.userId, !user.isCloseFriend);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(user.isCloseFriend
              ? 'Removed from Close Friends'
              : 'Added to Close Friends'),
        ),
      );
    } catch (e) {
      debugPrint('Close friend toggle failed: $e');
    }
  }

  @override
  void dispose() {
    _searchRequestId++;
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: 'Suggest Friends',
      subtitle: 'Find and connect with people',
      navIndex: 0,
      body: _buildBody(),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Search bar
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
          accountId: widget.recentSearchAccountId,
          onSelected: _selectRecentSearch,
        ),
        // Category tabs (hidden during search)
        if (_search.text.trim().isEmpty)
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final selected = index == _selectedCategoryIndex;
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.icon, size: 16, color: selected ? _P.darkOnAccent : _P.muted),
                      const SizedBox(width: 6),
                      Text(cat.label),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) => _onCategoryChanged(index),
                  selectedColor: _P.primary,
                  backgroundColor: _P.surface,
                  labelStyle: TextStyle(
                    color: selected ? _P.darkOnAccent : _P.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: selected ? _P.primary : _P.border,
                    width: 1.2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                );
              },
            ),
          ),

        // Content
        Expanded(
          child: _search.text.trim().isEmpty
              ? _buildCategoryView()
              : _buildSearchView(),
        ),
      ],
    );
  }

  Widget _buildCategoryView() {
    final category = _categories[_selectedCategoryIndex].id;
    final suggestions = _categoryCache[category];
    final failed = _failedCategories.contains(category);
    Future<void> refresh() => _loadCategory(category, refresh: true);

    if (suggestions == null && _loadingCategories.contains(category)) {
      return _buildSkeleton();
    }

    final errorBanner = failed
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _buildError(
              message: "We couldn't load suggestions. Please try again.",
              onRetry: refresh,
            ),
          )
        : null;

    return RefreshIndicator(
      onRefresh: refresh,
      color: _P.primary,
      child: CustomScrollView(
        key: PageStorageKey('suggestions-$category'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (errorBanner != null) SliverToBoxAdapter(child: errorBanner),
          if (suggestions == null || suggestions.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: failed
                  ? const SizedBox.shrink()
                  : _buildEmptyState(category),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              sliver: SliverList.builder(
                itemCount: suggestions.length,
                itemBuilder: (context, index) =>
                    _buildSuggestion(suggestions[index], index),
              ),
            ),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestion(
    FriendSuggestion user,
    int index, {
    bool showFollow = true,
    bool fromSearch = false,
  }) =>
      FadeSlideIn(
        key: ValueKey(user.userId),
        index: index.clamp(0, 7),
        child: _SuggestionTile(
          user: user,
          onMessage: () {
            if (fromSearch) _rememberSearch(_search.text);
            _startDM(user);
          },
          onFollow: showFollow ? () => _toggleFollow(user) : null,
          onCloseFriend: () => _toggleCloseFriend(user),
          onProfileTap: () {
            if (fromSearch) _rememberSearch(_search.text);
            context.push('/profile/${user.userId}');
          },
        ),
      );

  Widget _buildSearchView() {
    if (_searchLoading) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [_buildSearchSkeleton()],
      );
    }
    if (_searchError != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        children: [
          _buildError(
            message: _searchError!,
            onRetry: () => _onSearchChanged(_search.text),
          ),
        ],
      );
    }
    if (_searchCompleted && _searchResults.isEmpty) {
      return ListView(
        children: [
          _SearchEmptyState(query: _search.text.trim(), onClear: _clearSearch),
        ],
      );
    }
    if (_searchResults.isEmpty) return const SizedBox.shrink();

    return ListView.builder(
      key: const ValueKey('people-search-results'),
      itemCount: _searchResults.length + 1,
      padding: const EdgeInsets.only(bottom: 8),
      itemBuilder: (context, index) {
        if (index > 0) {
          return _buildSuggestion(
            _searchResults[index - 1],
            index - 1,
            showFollow: _searchFollowReady,
            fromSearch: true,
          );
        }
        if (_searchFollowFailed) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: _buildError(
              message: "Follow buttons couldn't load. You can still open a profile or chat.",
              onRetry: () => _loadSearchFollowStatus(_searchRequestId),
            ),
          );
        }
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            'People',
            style: TextStyle(
              color: _P.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeleton() {
    final scheme = Theme.of(context).colorScheme;
    final block = scheme.onSurface.withValues(alpha: 0.08);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: block, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 160,
                      height: 16,
                      decoration: BoxDecoration(
                        color: block,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 200,
                      height: 12,
                      decoration: BoxDecoration(
                        color: block,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 120,
                      height: 28,
                      decoration: BoxDecoration(
                        color: block,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String category) {
    String title, message;
    IconData icon;
    switch (category) {
      case 'circles':
        title = 'No circle suggestions';
        message = 'Join circles to see people from your communities here.';
        icon = Icons.group_outlined;
        break;
      case 'mutual':
        title = 'No mutual connections';
        message = 'As you connect with more people, mutual connections will appear.';
        icon = Icons.handshake_outlined;
        break;
      case 'groups':
        title = 'No shared groups';
        message = 'Participate in group chats to find people from your groups.';
        icon = Icons.forum_outlined;
        break;
      case 'followers':
        title = 'No new followers';
        message = 'People who follow you will appear here.';
        icon = Icons.person_add_alt_1_outlined;
        break;
      default:
        title = 'No suggestions yet';
        message = 'As you use the app, we\'ll suggest people you may know.';
        icon = Icons.people_outline;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _P.surfaceHigh,
                shape: BoxShape.circle,
                border: Border.all(color: _P.border),
              ),
              child: Icon(icon, color: _P.primary, size: 40),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    color: _P.text, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: _P.muted, fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final category = _categories[_selectedCategoryIndex].id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          category == 'all' ? 'End of suggestions' : 'No more in this category',
          style: TextStyle(color: _P.muted, fontSize: 13),
        ),
      ),
    );
  }

  // ===== Search UI Components =====

  Widget _buildSearchSkeleton() {
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
                  decoration: BoxDecoration(color: block, shape: BoxShape.circle),
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

  Widget _buildError({required String message, required VoidCallback onRetry}) {
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

  Widget _SearchEmptyState({required String query, required VoidCallback onClear}) {
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
}

class _CategoryTab {
  final String id;
  final String label;
  final IconData icon;

  _CategoryTab({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// Enhanced Suggestion Tile with quick actions and suggestion reason
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.user,
    required this.onMessage,
    required this.onFollow,
    required this.onCloseFriend,
    required this.onProfileTap,
  });

  final FriendSuggestion user;
  final VoidCallback onMessage;
  final VoidCallback? onFollow;
  final VoidCallback onCloseFriend;
  final VoidCallback onProfileTap;

  @override
  Widget build(BuildContext context) {
    final isOnline = user.isOnline;
    final mutualText = user.mutualCount > 0
        ? '${user.mutualCount} mutual connection${user.mutualCount > 1 ? 's' : ''}'
        : null;

    return PressScale(
      scaleFactor: 0.98,
      onTap: onMessage,
      onLongPress: onProfileTap,
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
            onTap: onMessage,
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
                          size: 52,
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
                  // Info section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _P.text,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15.5,
                                ),
                              ),
                            ),
                            if (user.isCloseFriend)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _P.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.star_rounded, size: 10, color: _P.primary),
                                    const SizedBox(width: 2),
                                    Text('Close Friend',
                                        style: TextStyle(
                                          color: _P.primary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        )),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '@${user.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _P.muted, fontSize: 12.5),
                        ),
                        if (user.suggestionReason.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _getSuggestionIcon(user.suggestionType),
                                size: 11,
                                color: _P.muted.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  user.suggestionReason,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _P.muted.withValues(alpha: 0.7),
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (mutualText != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.people_outline, size: 11, color: _P.primary),
                              const SizedBox(width: 4),
                              Text(
                                mutualText,
                                style: TextStyle(
                                  color: _P.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Follow/Following button
                      if (onFollow != null && !user.isFollowing) ...[
                        PressScale(
                          scaleFactor: 0.92,
                          onTap: onFollow,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: _P.primary,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: _P.primary.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_add_rounded, size: 14, color: _P.darkOnAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'Follow',
                                  style: TextStyle(
                                    color: _P.darkOnAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else if (onFollow != null) ...[
                        PressScale(
                          scaleFactor: 0.92,
                          onTap: onFollow,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: _P.surfaceHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _P.border.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_rounded, size: 14, color: _P.success),
                                const SizedBox(width: 4),
                                Text(
                                  'Following',
                                  style: TextStyle(
                                    color: _P.muted,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Message button
                      PressScale(
                        scaleFactor: 0.92,
                        onTap: onMessage,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: _P.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _P.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: _P.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Message',
                                style: TextStyle(
                                  color: _P.primary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getSuggestionIcon(String type) {
    switch (type) {
      case 'From your circles':
        return Icons.group_outlined;
      case 'Mutual connections':
        return Icons.handshake_outlined;
      case 'Shared groups':
        return Icons.forum_outlined;
      case 'Follows you':
        return Icons.person_add_alt_1_outlined;
      default:
        return Icons.psychology_outlined;
    }
  }
}

// Extension to convert FriendSuggestion to Profile for chat navigation
extension FriendSuggestionExt on FriendSuggestion {
  Profile toProfile() => Profile(
        id: userId,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        photoVisibility: 'everyone',
        statusVisibility: 'everyone',
        aboutVisibility: 'everyone',
        readReceiptsEnabled: true,
      );
}