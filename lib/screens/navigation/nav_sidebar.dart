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
      width: 250,
      decoration: const BoxDecoration(
        color: app_colors.P.surface,
        border: Border(
          right: BorderSide(color: Color(0xFF292A2F), width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/bro_logo.png',
                    width: 38,
                    height: 38,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.flash_on,
                      color: app_colors.P.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'BRO',
                    style: TextStyle(
                      color: app_colors.P.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF292A2F), height: 1),
            const SizedBox(height: 12),
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
            const Divider(color: Color(0xFF292A2F), height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: app_colors.P.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: app_colors.P.border.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: app_colors.P.primary,
                      child: Text(
                        (Supa.currentUser?.email?.isNotEmpty ?? false)
                            ? Supa.currentUser!.email![0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: app_colors.P.darkOnAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        Supa.currentUser?.email ?? '',
                        style: const TextStyle(
                          color: app_colors.P.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? app_colors.P.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? app_colors.P.primary.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 20,
                color: selected ? app_colors.P.primary : app_colors.P.muted,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: selected ? app_colors.P.primary : app_colors.P.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
