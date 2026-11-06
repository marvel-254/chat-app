// Followers / Following Screen (Full Page)
// Full-screen followers/following list with search, pagination, and pull-to-refresh.
// Replaces the previous bottom sheet implementation for better UX on mobile.

import 'dart:async';

import 'package:flutter/material.dart';

import 'services/supabase.dart';
import 'models/profile.dart';

/// Color palette matching the app's design tokens.
/// Duplicated here to avoid importing private _P from main.dart.
class _FollowColors {
  static const Color background = Color(0xFF121318);
  static const Color surface = Color(0xFF1A1C24);
  static const Color primary = Color(0xFF00D4AA);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF8B9099);
  static const Color border = Color(0xFF2E323D);
}

class FollowersFollowingScreen extends StatefulWidget {
  const FollowersFollowingScreen({
    super.key,
    required this.userId,
    this.initialTab = 0,
    required this.onOpenProfile,
  });
  final String userId;
  final int initialTab;
  final void Function(String userId) onOpenProfile;

  @override
  State<FollowersFollowingScreen> createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Followers state
  List<Profile> _followers = [];
  bool _loadingFollowers = false;
  bool _followersHasMore = true;
  int _followersOffset = 0;
  static const int _pageSize = 30;
  String _followersSearchQuery = '';
  Timer? _followersSearchDebounce;

  // Following state
  List<Profile> _following = [];
  bool _loadingFollowing = false;
  bool _followingHasMore = true;
  int _followingOffset = 0;
  String _followingSearchQuery = '';
  Timer? _followingSearchDebounce;

  // Shared
  final _scrollControllers = <int, ScrollController>{};
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _currentUserId = Supa.currentUser?.id;
    _loadInitialData();
    _tabs.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _followersSearchDebounce?.cancel();
    _followingSearchDebounce?.cancel();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      _ensureScrollController(_tabs.index);
      // Trigger load more if near bottom
      _maybeLoadMore(_tabs.index);
    }
  }

  ScrollController _getScrollController(int tabIndex) {
    return _scrollControllers.putIfAbsent(tabIndex, () {
      final controller = ScrollController();
      controller.addListener(() {
        if (controller.position.pixels >= controller.position.maxScrollExtent - 200) {
          _maybeLoadMore(tabIndex);
        }
      });
      return controller;
    });
  }

  void _ensureScrollController(int tabIndex) {
    _getScrollController(tabIndex);
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadFollowers(reset: true),
      _loadFollowing(reset: true),
    ]);
  }

  Future<void> _loadFollowers({bool reset = false}) async {
    if (_loadingFollowers) return;
    if (reset) {
      _followersOffset = 0;
      _followersHasMore = true;
    }
    if (!_followersHasMore && !reset) return;

    setState(() => _loadingFollowers = true);
    try {
      final list = await Supa.getFollowing(widget.userId);
      if (mounted) {
        setState(() {
          if (reset) {
            _followers = list;
          } else {
            _followers.addAll(list);
          }
          _followersOffset += list.length;
          _followersHasMore = list.length >= _pageSize;
          _loadingFollowers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (reset) _followers = [];
          _loadingFollowers = false;
          _followersHasMore = false;
        });
      }
    }
  }

  Future<void> _loadFollowing({bool reset = false}) async {
    if (_loadingFollowing) return;
    if (reset) {
      _followingOffset = 0;
      _followingHasMore = true;
    }
    if (!_followingHasMore && !reset) return;

    setState(() => _loadingFollowing = true);
    try {
      final list = await Supa.getFollowing(
        widget.userId,
        limit: _pageSize,
        offset: _followingOffset,
        search: _followingSearchQuery.isEmpty ? null : _followingSearchQuery,
      );
      if (mounted) {
        setState(() {
          if (reset) {
            _following = list;
          } else {
            _following.addAll(list);
          }
          _followingOffset += list.length;
          _followingHasMore = list.length >= _pageSize;
          _loadingFollowing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (reset) _following = [];
          _loadingFollowing = false;
          _followingHasMore = false;
        });
      }
    }
  }

  void _maybeLoadMore(int tabIndex) {
    if (tabIndex == 0) {
      _loadFollowers();
    } else {
      _loadFollowing();
    }
  }

  void _onFollowersSearchChanged(String query) {
    _followersSearchDebounce?.cancel();
    _followersSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _followersSearchQuery = query.trim());
        _loadFollowers(reset: true);
      }
    });
  }

  void _onFollowingSearchChanged(String query) {
    _followingSearchDebounce?.cancel();
    _followingSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _followingSearchQuery = query.trim());
        _loadFollowing(reset: true);
      }
    });
  }

  Future<void> _onRefresh(int tabIndex) async {
    if (tabIndex == 0) {
      await _loadFollowers(reset: true);
    } else {
      await _loadFollowing(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FollowColors.background,
      appBar: AppBar(
        title: const Text('Followers & Following'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: _FollowColors.background,
        foregroundColor: _FollowColors.text,
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabs,
          labelColor: _FollowColors.primary,
          unselectedLabelColor: _FollowColors.muted,
          indicatorColor: _FollowColors.primary,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: [
            Tab(
              text: 'Followers${_followers.isNotEmpty ? '  ${_fmtCount(_followers.length)}' : ''}',
            ),
            Tab(
              text: 'Following${_following.isNotEmpty ? '  ${_fmtCount(_following.length)}' : ''}',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildList(
            tabIndex: 0,
            profiles: _followers,
            loading: _loadingFollowers,
            hasMore: _followersHasMore,
            searchQuery: _followersSearchQuery,
            onSearchChanged: _onFollowersSearchChanged,
            onRefresh: () => _onRefresh(0),
          ),
          _buildList(
            tabIndex: 1,
            profiles: _following,
            loading: _loadingFollowing,
            hasMore: _followingHasMore,
            searchQuery: _followingSearchQuery,
            onSearchChanged: _onFollowingSearchChanged,
            onRefresh: () => _onRefresh(1),
          ),
        ],
      ),
    );
  }

  Widget _buildList({
    required int tabIndex,
    required List<Profile> profiles,
    required bool loading,
    required bool hasMore,
    required String searchQuery,
    required ValueChanged<String> onSearchChanged,
    required Future<void> Function() onRefresh,
  }) {
    final controller = _getScrollController(tabIndex);
    final isEmpty = profiles.isEmpty && !loading;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: _FollowColors.primary,
      child: CustomScrollView(
        controller: controller,
        slivers: [
          // Search bar sliver
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SearchField(
                query: searchQuery,
                onChanged: onSearchChanged,
                hintText: tabIndex == 0
                    ? 'Search followers...'
                    : 'Search following...',
              ),
            ),
          ),
          // List content
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                tabIndex: tabIndex,
                hasSearch: searchQuery.isNotEmpty,
                onClearSearch: searchQuery.isNotEmpty ? () => onSearchChanged('') : null,
              ),
            )
          else
            SliverList.separated(
              key: ValueKey('list-$tabIndex'),
              itemCount: profiles.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: _FollowColors.border.withValues(alpha: 0.5),
                indent: 72,
              ),
              itemBuilder: (context, index) {
                if (index >= profiles.length) {
                  return _LoadingMoreIndicator(loading: loading);
                }
                final profile = profiles[index];
                return _FollowListTile(
                  key: ValueKey(profile.id),
                  profile: profile,
                  isCurrentUser: profile.id == _currentUserId,
                  onTap: () => widget.onOpenProfile(profile.id),
                );
              },
            ),
          // Load more / end indicator
          if (hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            )
          else if (!isEmpty && profiles.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'You\'ve seen everyone',
                    style: TextStyle(color: _FollowColors.muted, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// Search field widget used in the followers/following lists.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.query,
    required this.onChanged,
    required this.hintText,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: _FollowColors.muted, fontSize: 14),
        prefixIcon: Icon(Icons.search, color: _FollowColors.muted, size: 20),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: Icon(Icons.clear, color: _FollowColors.muted, size: 20),
                onPressed: () => onChanged(''),
                tooltip: 'Clear search',
              )
            : null,
        filled: true,
        fillColor: _FollowColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _FollowColors.primary, width: 1.5),
        ),
      ),
      style: TextStyle(color: _FollowColors.text, fontSize: 14),
      textInputAction: TextInputAction.search,
    );
  }
}

/// Empty state widget for followers/following lists.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.tabIndex,
    required this.hasSearch,
    this.onClearSearch,
  });

  final int tabIndex;
  final bool hasSearch;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final label = tabIndex == 0 ? 'followers' : 'following';
    final icon = tabIndex == 0 ? Icons.people_outline : Icons.person_add_outlined;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: _FollowColors.muted.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              hasSearch ? 'No $label found' : 'No $label yet',
              style: const TextStyle(
                color: _FollowColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try a different search term'
                  : 'When someone follows you, they\'ll appear here',
              textAlign: TextAlign.center,
              style: TextStyle(color: _FollowColors.muted, fontSize: 14, height: 1.5),
            ),
            if (hasSearch && onClearSearch != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear search'),
                style: TextButton.styleFrom(foregroundColor: _FollowColors.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading indicator shown at the bottom of the list when fetching more.
class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _FollowColors.primary,
          ),
        ),
      ),
    );
  }
}

/// List tile for a follower/following item.
class _FollowListTile extends StatelessWidget {
  const _FollowListTile({
    super.key,
    required this.profile,
    required this.isCurrentUser,
    required this.onTap,
  });

  final Profile profile;
  final bool isCurrentUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Avatar
              _FollowAvatar(
                name: profile.peerInitial,
                url: profile.avatarUrl,
                size: 44,
              ),
              const SizedBox(width: 12),
              // Name + username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.label,
                      style: const TextStyle(
                        color: _FollowColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${profile.username}',
                      style: TextStyle(
                        color: _FollowColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Follow button (not for current user)
              if (!isCurrentUser)
                _FollowToggleButton(userId: profile.id)
              else
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: _FollowColors.muted.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'You',
                      style: TextStyle(
                        color: _FollowColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar widget for follower/following list items.
class _FollowAvatar extends StatelessWidget {
  const _FollowAvatar({
    super.key,
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = [
      _FollowColors.primary,
      const Color(0xFF6366F1),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFFEC4899),
      const Color(0xFF14B8A6),
    ];
    final colorIndex = name.codeUnitAt(0) % colors.length;
    final bgColor = colors[colorIndex];

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: bgColor,
      backgroundImage: url != null && url!.isNotEmpty ? NetworkImage(url!) : null,
      child: url == null || url!.isEmpty
          ? Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

/// A small follow/unfollow toggle button used inside list tiles.
class _FollowToggleButton extends StatefulWidget {
  const _FollowToggleButton({required this.userId});
  final String userId;

  @override
  State<_FollowToggleButton> createState() => _FollowToggleButtonState();
}

class _FollowToggleButtonState extends State<_FollowToggleButton> {
  bool? _following; // null = loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Supa.isFollowing(widget.userId).then((v) {
      if (mounted) setState(() => _following = v);
    }).catchError((_) {
      if (mounted) setState(() => _following = false);
    });
  }

  Future<void> _toggle() async {
    final current = _following;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Supa.setFollowing(widget.userId, !current);
      if (mounted) setState(() => _following = !current);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_following == null) {
      return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _busy
          ? const SizedBox(
              key: ValueKey('busy'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _FollowColors.primary))
          : OutlinedButton(
              key: ValueKey(_following),
              onPressed: _toggle,
              style: OutlinedButton.styleFrom(
                foregroundColor: _following! ? _FollowColors.muted : _FollowColors.primary,
                side: BorderSide(
                    color: _following! ? _FollowColors.border : _FollowColors.primary, width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(80, 32),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_following! ? 'Following' : 'Follow'),
            ),
    );
  }
}