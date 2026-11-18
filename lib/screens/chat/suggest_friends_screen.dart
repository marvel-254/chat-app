import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/presence.dart';
import '../../models/profile.dart';
import '../../ui/states.dart';
import '../../ui/motion.dart';
import 'widgets/avatar.dart';
import '../../widgets/responsive_app_shell.dart';

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
  const SuggestFriendsScreen({super.key});
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

  // Category tabs
  final _categories = [
    _CategoryTab(id: 'all', label: 'All', icon: Icons.people_outline),
    _CategoryTab(id: 'circles', label: 'From Circles', icon: Icons.group_outlined),
    _CategoryTab(id: 'mutual', label: 'Mutual Connections', icon: Icons.handshake_outlined),
    _CategoryTab(id: 'groups', label: 'Shared Groups', icon: Icons.forum_outlined),
    _CategoryTab(id: 'followers', label: 'Followers', icon: Icons.person_add_alt_1_outlined),
  ];

  int _selectedCategoryIndex = 0;
  Map<String, List<FriendSuggestion>> _categoryCache = {};
  Set<String> _loadingCategories = {};
  Set<String> _completedCategories = {};

  @override
  void initState() {
    super.initState();
    _loadCategory('all');
  }

  Future<void> _loadCategory(String category) async {
    if (_completedCategories.contains(category) || _loadingCategories.contains(category)) return;
    setState(() => _loadingCategories.add(category));
    try {
      final results = await Supa.getFriendSuggestionsByCategory(category, limit: 20);
      if (!mounted) return;
      setState(() {
        _categoryCache[category] = results;
        _completedCategories.add(category);
        _loadingCategories.remove(category);
      });
    } catch (e) {
      debugPrint('Failed to load category $category: $e');
      if (!mounted) return;
      setState(() => _loadingCategories.remove(category));
    }
  }

  void _onCategoryChanged(int index) {
    setState(() => _selectedCategoryIndex = index);
    final category = _categories[index].id;
    _loadCategory(category);
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

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchLoading = true);
      try {
        final results = await Supa.searchUsers(query);
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
    try {
      await Supa.setFollowing(user.userId, !user.isFollowing);
      if (!mounted) return;
      // Update local cache
      setState(() {
        final currentCategory = _categories[_selectedCategoryIndex].id;
        final list = _categoryCache[currentCategory];
        if (list != null) {
          final idx = list.indexWhere((u) => u.userId == user.userId);
          if (idx != -1) {
            _categoryCache[currentCategory] = [
              ...list.take(idx),
              FriendSuggestion(
                userId: user.userId,
                username: user.username,
                displayName: user.displayName,
                avatarUrl: user.avatarUrl,
                lastSeenAt: user.lastSeenAt,
                isOnline: user.isOnline,
                mutualCount: user.mutualCount,
                suggestionReason: user.suggestionReason,
                suggestionType: user.suggestionType,
                isFollowing: !user.isFollowing,
                isCloseFriend: user.isCloseFriend,
                profileStatus: user.profileStatus,
                profileColor: user.profileColor,
              ),
              ...list.skip(idx + 1),
            ];
          }
        }
      });
    } catch (e) {
      debugPrint('Follow failed: $e');
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
      body: _buildBody(context),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
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
              onChanged: _onSearchChanged,
              onTapOutside: (_) => _searchFocusNode.unfocus(),
            ),
          ),
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
              ? _buildCategoryView(context)
              : _buildSearchView(context),
        ),
      ],
    );
  }

  Widget _buildCategoryView(BuildContext context) {
    final category = _categories[_selectedCategoryIndex].id;
    final suggestions = _categoryCache[category] ?? [];
    final isLoading = _loadingCategories.contains(category);

    if (isLoading && suggestions.isEmpty) {
      return _buildSkeleton();
    }

    if (suggestions.isEmpty) {
      return _buildEmptyState(category);
    }

    return RefreshIndicator(
      onRefresh: () => _loadCategory(category),
      color: _P.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: suggestions.length + 1, // +1 for footer
        itemBuilder: (context, index) {
          if (index == suggestions.length) {
            // Footer with "Load more" or end message
            return _buildFooter(context);
          }
          final user = suggestions[index];
          return FadeSlideIn(
            index: index.clamp(0, 7),
            child: _SuggestionTile(
              user: user,
              onMessage: () => _startDM(user),
              onFollow: () => _toggleFollow(user),
              onCloseFriend: () => _toggleCloseFriend(user),
              onProfileTap: () => context.push('/profile/${user.userId}'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchView(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Loading skeleton
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _searchLoading
                ? Padding(
                    key: const ValueKey('loading'),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _SearchSkeleton(),
                  )
                : const SizedBox(key: ValueKey('no-loading'), height: 0),
          ),
          // Error state
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: _SearchError(
                message: _searchError!,
                onRetry: () => _onSearchChanged(_search.text),
              ),
            ),
          // Empty state
          if (_searchCompleted &&
              _searchError == null &&
              _searchResults.isEmpty)
            _SearchEmptyState(
              query: _search.text.trim(),
              onClear: _clearSearch,
            ),
          // Search results
          if (_searchResults.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                'People',
                style: TextStyle(
                    color: _P.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              padding: const EdgeInsets.only(bottom: 8),
              itemBuilder: (context, index) {
                final u = _searchResults[index];
                return FadeSlideIn(
                  index: index.clamp(0, 7),
                  child: _SuggestionTile(
                    user: u,
                    onMessage: () => _startDM(u),
                    onFollow: () => _toggleFollow(u),
                    onCloseFriend: () => _toggleCloseFriend(u),
                    onProfileTap: () => context.push('/profile/${u.userId}'),
                  ),
                );
              },
            ),
          ],
        ],
      ),
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

  Widget _buildFooter(BuildContext context) {
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

  Widget _SearchSkeleton() {
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

  Widget _SearchError({required String message, required VoidCallback onRetry}) {
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
  final VoidCallback onFollow;
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
                      if (!user.isFollowing) ...[
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
                      ] else ...[
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