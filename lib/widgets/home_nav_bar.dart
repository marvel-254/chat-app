import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Chats / Circles / Status bottom bar shared by the app surfaces.
class HomeNavBar extends StatelessWidget {
  const HomeNavBar({super.key, required this.index});

  /// 0 = Chats, 1 = Circles, 2 = Status, 3 = Calls.
  final int index;

  static const _surface = Color(0xFF1E1F25);
  static const _surfaceBorder = Color(0xFF292A2F);
  static const _primary = Color(0xFFD4FF00);
  static const _muted = Color(0xFFC5C9AC);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _surfaceBorder, width: 1)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 68,
          indicatorColor: _primary.withValues(alpha: 0.16),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _primary.withValues(alpha: 0.3), width: 1),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _primary : _muted,
              letterSpacing: 0.2,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(color: selected ? _primary : _muted, size: 23);
          }),
        ),
        child: NavigationBar(
          selectedIndex: index.clamp(0, 3),
          animationDuration: const Duration(milliseconds: 300),
          onDestinationSelected: (i) {
            if (i == index) return;
            if (i == 0) context.go('/conversations');
            if (i == 1) context.go('/circles');
            if (i == 2) context.go('/status');
            if (i == 3) context.go('/recent-calls');
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Circles',
            ),
            NavigationDestination(
              icon: Icon(Icons.slow_motion_video_outlined),
              selectedIcon: Icon(Icons.slow_motion_video_rounded),
              label: 'Status',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              selectedIcon: Icon(Icons.call),
              label: 'Calls',
            ),
          ],
        ),
      ),
    );
  }
}
