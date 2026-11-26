// Followers / Following screen.
// Full-page people lists with search, pagination, pull-to-refresh and a
// responsive two-pane desktop layout. Uses the shared BRO design tokens.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart' as app_colors;
import '../ui/errors.dart';
import '../ui/states.dart';
import '../widgets/responsive_app_shell.dart';
import 'screens/chat/widgets/avatar.dart';
import 'models/profile.dart';
import 'services/supabase.dart';

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
  State<FollowersFollowingScreen> createState() =>
      _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 30;

  late final TabController _tabs;
  final FocusNode _listFocusNode = FocusNode(debugLabel: 'follow-list');
  final _scrollControllers = <int, ScrollController>{};

  List<Profile> _followers = <Profile>[];
  List<Profile> _following = <Profile>[];
  bool _loadingFollowers = false;
  bool _loadingFollowing = false;
  bool _followersHasMore = true;
  bool _followingHasMore = true;
  int _followersOffset = 0;
  int _followingOffset = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  String _followersSearchQuery = '';
  String _followingSearchQuery = '';
  Timer? _followersSearchDebounce;
  Timer? _followingSearchDebounce;
  String? _currentUserId;
  int _keyboardIndex = 0;
  int _activePane = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _activePane = widget.initialTab;
    _currentUserId = Supa.currentUser?.id;
    _tabs.addListener(_onTabChanged);
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _listFocusNode.dispose();
    _followersSearchDebounce?.cancel();
    _followingSearchDebounce?.cancel();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      _activePane = _tabs.index;
      _getScrollController(_activePane);
      _maybeLoadMore(_activePane);
    }
  }

  ScrollController _getScrollController(int tabIndex) {
    return _scrollControllers.putIfAbsent(tabIndex, () {
      final controller = ScrollController();
      controller.addListener(() {
        if (controller.hasClients &&
            controller.position.pixels >=
                controller.position.maxScrollExtent - 200) {
          _maybeLoadMore(tabIndex);
        }
      });
      return controller;
    });
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _loadFollowers(reset: true),
      _loadFollowing(reset: true),
      _loadCounts(),
    ]);
  }

  Future<void> _loadCounts() async {
    try {
      final counts = await Future.wait([
        Supa.getFollowersCount(widget.userId),
        Supa.getFollowingCount(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _followersCount = counts[0];
        _followingCount = counts[1];
      });
    } catch (_) {
      // Counts are cosmetic; the lists remain usable.
    }
  }

  Future<void> _loadFollowers({bool reset = false}) async {
    if (_loadingFollowers) return;
    if (!_followersHasMore && !reset) return;
    if (mounted) setState(() => _loadingFollowers = true);
    try {
      final list = await Supa.getFollowers(
        widget.userId,
        limit: _pageSize,
        offset: reset ? 0 : _followersOffset,
        search: _followersSearchQuery.isEmpty ? null : _followersSearchQuery,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _followers = list;
          _followersOffset = list.length;
        } else {
          _followers.addAll(list);
          _followersOffset += list.length;
        }
        _followersHasMore = list.length >= _pageSize;
        _loadingFollowers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (reset) {
          _followers = <Profile>[];
          _followersOffset = 0;
        }
        _followersHasMore = false;
        _loadingFollowers = false;
      });
    }
  }

  Future<void> _loadFollowing({bool reset = false}) async {
    if (_loadingFollowing) return;
    if (!_followingHasMore && !reset) return;
    if (mounted) setState(() => _loadingFollowing = true);
    try {
      final list = await Supa.getFollowing(
        widget.userId,
        limit: _pageSize,
        offset: reset ? 0 : _followingOffset,
        search: _followingSearchQuery.isEmpty ? null : _followingSearchQuery,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _following = list;
          _followingOffset = list.length;
        } else {
          _following.addAll(list);
          _followingOffset += list.length;
        }
        _followingHasMore = list.length >= _pageSize;
        _loadingFollowing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (reset) {
          _following = <Profile>[];
          _followingOffset = 0;
        }
        _followingHasMore = false;
        _loadingFollowing = false;
      });
    }
  }

  void _maybeLoadMore(int tabIndex) {
    if (tabIndex == 0) {
      unawaited(_loadFollowers());
    } else {
      unawaited(_loadFollowing());
    }
  }

  void _onSearchChanged(int tabIndex, String value) {
    final query = value.trim();
    if (tabIndex == 0) {
      _followersSearchDebounce?.cancel();
      _followersSearchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _followersSearchQuery = query);
        unawaited(_loadFollowers(reset: true));
      });
    } else {
      _followingSearchDebounce?.cancel();
      _followingSearchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _followingSearchQuery = query);
        unawaited(_loadFollowing(reset: true));
      });
    }
  }

  Future<void> _onRefresh(int tabIndex) async {
    if (tabIndex == 0) {
      await _loadFollowers(reset: true);
    } else {
      await _loadFollowing(reset: true);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final list = _activePane == 0 ? _followers : _following;
    if (list.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final step =
          event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() {
        _keyboardIndex = (_keyboardIndex + step).clamp(0, list.length - 1);
      });
      _getScrollController(_activePane).animateTo(
        (_keyboardIndex * 72).clamp(
          0.0,
          _getScrollController(_activePane).position.maxScrollExtent,
        ).toDouble(),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_keyboardIndex < list.length) {
        widget.onOpenProfile(list[_keyboardIndex].id);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: 'Followers & Following',
      subtitle: 'People connected to this profile',
      navIndex: 0,
      showBottomNavigation: false,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      body: Focus(
        focusNode: _listFocusNode,
        onKeyEvent: _onKeyEvent,
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= app_colors.desktopBreakpoint) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildPane(0, showHeader: true)),
                VerticalDivider(
                  width: 1,
                  color: app_colors.border.withValues(alpha: 0.4),
                ),
                Expanded(child: _buildPane(1, showHeader: true)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _buildPane(0, showHeader: false),
                    _buildPane(1, showHeader: false),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: app_colors.border.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabs,
        labelColor: app_colors.volt,
        unselectedLabelColor: app_colors.muted,
        indicatorColor: app_colors.volt,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: [
          Tab(text: 'Followers   ${_fmtCount(_followersCount)}'),
          Tab(text: 'Following   ${_fmtCount(_followingCount)}'),
        ],
      ),
    );
  }

  Widget _buildPane(int tabIndex, {required bool showHeader}) {
    final isFollowers = tabIndex == 0;
    final profiles = isFollowers ? _followers : _following;
    final loading = isFollowers ? _loadingFollowers : _loadingFollowing;
    final hasMore = isFollowers ? _followersHasMore : _followingHasMore;
    final query =
        isFollowers ? _followersSearchQuery : _followingSearchQuery;
    final count = isFollowers ? _followersCount : _followingCount;
    final controller = _getScrollController(tabIndex);
    final isEmpty = profiles.isEmpty && !loading;
    final showSkeleton = profiles.isEmpty && loading;

    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) _activePane = tabIndex;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Row(
                children: [
                  Icon(
                    isFollowers
                        ? Icons.people_outline_rounded
                        : Icons.how_to_reg_outlined,
                    size: 18,
                    color: app_colors.volt,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isFollowers ? 'Followers' : 'Following',
                    style: const TextStyle(
                      color: app_colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _fmtCount(count),
                    style: const TextStyle(
                      color: app_colors.muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
            child: _SearchField(
              query: query,
              hintText: isFollowers
                  ? 'Search followers'
                  : 'Search following',
              onChanged: (value) => _onSearchChanged(tabIndex, value),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _onRefresh(tabIndex),
              color: app_colors.volt,
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  if (showSkeleton)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: ListSkeleton(label: 'Loading people'),
                    )
                  else if (isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        tabIndex: tabIndex,
                        hasSearch: query.isNotEmpty,
                        onClearSearch: query.isNotEmpty
                            ? () => _onSearchChanged(tabIndex, '')
                            : null,
                      ),
                    )
                  else
                    SliverList.separated(
                      key: ValueKey('people-list-$tabIndex'),
                      itemCount: profiles.length + (hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: app_colors.border.withValues(alpha: 0.35),
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
                          highlighted: index == _keyboardIndex &&
                              _activePane == tabIndex,
                          onTap: () => widget.onOpenProfile(profile.id),
                        );
                      },
                    ),
                  if (!isEmpty && !showSkeleton && hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child:
                              loading ? const BroSpinner(size: 22) : const SizedBox.shrink(),
                        ),
                      ),
                    )
                  else if (!isEmpty && !showSkeleton && profiles.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            "You've seen everyone",
                            style: const TextStyle(
                              color: app_colors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.query,
    required this.hintText,
    required this.onChanged,
  });

  final String query;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: app_colors.muted, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: app_colors.muted,
          size: 20,
        ),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(
                  Icons.clear_rounded,
                  color: app_colors.muted,
                  size: 20,
                ),
                onPressed: () => onChanged(''),
              )
            : null,
        filled: true,
        fillColor: app_colors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: app_colors.volt, width: 1.5),
        ),
      ),
      style: const TextStyle(color: app_colors.text, fontSize: 14),
      textInputAction: TextInputAction.search,
    );
  }
}

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tabIndex == 0
                  ? Icons.people_outline_rounded
                  : Icons.person_add_outlined,
              size: 56,
              color: app_colors.muted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch ? 'No $label found' : 'No $label yet',
              style: const TextStyle(
                color: app_colors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try a different search term'
                  : 'When someone connects with this profile, they appear here',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: app_colors.muted,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (hasSearch && onClearSearch != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: const Text('Clear search'),
                style: TextButton.styleFrom(foregroundColor: app_colors.volt),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: BroSpinner(size: 22)),
    );
  }
}

class _FollowListTile extends StatelessWidget {
  const _FollowListTile({
    super.key,
    required this.profile,
    required this.isCurrentUser,
    required this.highlighted,
    required this.onTap,
  });

  final Profile profile;
  final bool isCurrentUser;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted
            ? app_colors.volt.withValues(alpha: 0.05)
            : Colors.transparent,
      ),
      child: InkWell(
        onTap: onTap,
        hoverColor: app_colors.volt.withValues(alpha: 0.05),
        focusColor: app_colors.volt.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Avatar(
                name: profile.peerInitial,
                url: profile.avatarUrl,
                digitalConfig: profile.avatarConfig,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.label,
                      style: const TextStyle(
                        color: app_colors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${profile.username}',
                      style: const TextStyle(
                        color: app_colors.muted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrentUser)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: app_colors.muted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'You',
                    style: TextStyle(
                      color: app_colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                _FollowToggleButton(userId: profile.id),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowToggleButton extends StatefulWidget {
  const _FollowToggleButton({required this.userId});

  final String userId;

  @override
  State<_FollowToggleButton> createState() => _FollowToggleButtonState();
}

class _FollowToggleButtonState extends State<_FollowToggleButton> {
  bool? _following;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadState());
  }

  Future<void> _loadState() async {
    try {
      final value = await Supa.isFollowing(widget.userId);
      if (mounted) setState(() => _following = value);
    } catch (_) {
      if (mounted) setState(() => _following = false);
    }
  }

  Future<void> _toggle() async {
    final current = _following;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Supa.setFollowing(widget.userId, !current);
      if (mounted) setState(() => _following = !current);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(friendlyErrorMessage(error)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_following == null) {
      return const BroSpinner(size: 18);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _busy
          ? const BroSpinner(key: ValueKey('busy'), size: 18)
          : OutlinedButton(
              key: ValueKey(_following),
              onPressed: _toggle,
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    _following! ? app_colors.muted : app_colors.volt,
                side: BorderSide(
                  color:
                      _following! ? app_colors.border : app_colors.volt,
                  width: 1.2,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(80, 32),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(_following! ? 'Following' : 'Follow'),
            ),
    );
  }
}
