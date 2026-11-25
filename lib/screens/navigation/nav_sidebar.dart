import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../ui/motion.dart';

class NavSidebar extends StatelessWidget {
  const NavSidebar({super.key, this.compact = false});

  /// Renders a narrow 76 px icon-and-label rail for tablet widths.
  final bool compact;

  static String _currentEmail() {
    try {
      return Supa.currentUser?.email ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouter.maybeOf(context) != null
        ? GoRouterState.of(context).matchedLocation
        : '';
    final email = _currentEmail();
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    void go(String route) => GoRouter.maybeOf(context)?.go(route);

    final items = <({IconData icon, IconData selectedIcon, String label, bool selected, String route})>[
      (
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        label: 'Chats',
        selected: location.startsWith('/conversations') || location.startsWith('/chat'),
        route: '/conversations',
      ),
      (
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups_rounded,
        label: 'Circles',
        selected: location.startsWith('/circles'),
        route: '/circles',
      ),
      (
        icon: Icons.call_outlined,
        selectedIcon: Icons.call_rounded,
        label: 'Calls',
        selected: location.startsWith('/recent-calls'),
        route: '/recent-calls',
      ),
      (
        icon: Icons.slow_motion_video_outlined,
        selectedIcon: Icons.slow_motion_video_rounded,
        label: 'Status',
        selected: location.startsWith('/status'),
        route: '/status',
      ),
      (
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: 'Settings',
        selected: location.startsWith('/settings'),
        route: '/settings',
      ),
    ];

    return Container(
      width: compact ? 76 : 240,
      decoration: const BoxDecoration(
        color: app_colors.P.surface,
        border: Border(
          right: BorderSide(color: app_colors.P.border, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                20,
                compact ? 12 : 16,
                18,
              ),
              child: Row(
                mainAxisAlignment:
                    compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: app_colors.P.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.asset(
                      'assets/images/bro_logo.png',
                      width: 28,
                      height: 28,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.flash_on,
                        color: app_colors.P.primary,
                        size: 22,
                      ),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    const Text(
                      'BRO',
                      style: TextStyle(
                        color: app_colors.P.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(color: app_colors.P.border, height: 1),
            const SizedBox(height: 8),
            for (final item in items)
              NavItem(
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                label: item.label,
                selected: item.selected,
                compact: compact,
                onTap: () => go(item.route),
              ),
            const Spacer(),
            const Divider(color: app_colors.P.border, height: 1),
            Padding(
              padding: EdgeInsets.all(compact ? 10 : 12),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: app_colors.P.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: app_colors.P.border.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment:
                      compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: app_colors.P.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: app_colors.P.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          email,
                          style: const TextStyle(
                            color: app_colors.P.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = selected ? app_colors.P.primary : app_colors.P.muted;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: selected
                ? app_colors.P.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? app_colors.P.primary.withValues(alpha: 0.25)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 20,
                      color: color,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      selected ? selectedIcon : icon,
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
