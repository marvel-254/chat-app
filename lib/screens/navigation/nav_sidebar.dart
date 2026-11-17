import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';

class NavSidebar extends StatelessWidget {
  const NavSidebar({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: app_colors.P.surface,
        border: Border(right: BorderSide(color: app_colors.P.border, width: 1)),
      ),
      child: Column(children: [
        Image.asset('assets/images/bro_logo.png',
            width: 56, height: 56, gaplessPlayback: true),
        NavItem(
            icon: Icons.forum_outlined,
            label: 'Chats',
            onTap: () => context.go('/conversations')),
        NavItem(
            icon: Icons.slow_motion_video_outlined,
            label: 'Status',
            onTap: () => context.go('/status')),
        NavItem(icon: Icons.search, label: 'Discover', onTap: () {}),
        NavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.go('/settings')),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(Supa.currentUser?.email ?? '',
              style: const TextStyle(
                  color: app_colors.P.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem(
      {super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 22, color: app_colors.P.muted),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      color: app_colors.P.muted, fontSize: 15)),
            ]),
          )),
    );
  }
}
