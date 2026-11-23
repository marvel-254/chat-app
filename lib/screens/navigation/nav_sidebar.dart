import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../ui/motion.dart';

class NavSidebar extends StatelessWidget {
  const NavSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Container(
      width: 240,
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
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
              child: Row(
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
              ),
            ),
            const Divider(color: app_colors.P.border, height: 1),
            const SizedBox(height: 8),
            NavItem(
              icon: Icons.chat_bubble_outline_rounded,
              selectedIcon: Icons.chat_bubble_rounded,
              label: 'Chats',
              selected: location.startsWith('/conversations') || location.startsWith('/chat'),
              onTap: () => context.go('/conversations'),
            ),
            NavItem(
              icon: Icons.groups_outlined,
              selectedIcon: Icons.groups_rounded,
              label: 'Circles',
              selected: location.startsWith('/circles'),
              onTap: () => context.go('/circles'),
            ),
            NavItem(
              icon: Icons.call_outlined,
              selectedIcon: Icons.call_rounded,
              label: 'Calls',
              selected: location.startsWith('/recent-calls'),
              onTap: () => context.go('/recent-calls'),
            ),
            NavItem(
              icon: Icons.slow_motion_video_outlined,
              selectedIcon: Icons.slow_motion_video_rounded,
              label: 'Status',
              selected: location.startsWith('/status'),
              onTap: () => context.go('/status'),
            ),
            NavItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Settings',
              selected: location.startsWith('/settings'),
              onTap: () => context.go('/settings'),
            ),
            const Spacer(),
            const Divider(color: app_colors.P.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: app_colors.P.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: app_colors.P.border.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
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
                          (Supa.currentUser?.email?.isNotEmpty ?? false)
                              ? Supa.currentUser!.email![0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: app_colors.P.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Supa.currentUser?.email ?? '',
                            style: const TextStyle(
                              color: app_colors.P.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
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
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          child: Row(
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 18,
                color: selected ? app_colors.P.primary : app_colors.P.muted,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected ? app_colors.P.primary : app_colors.P.muted,
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
