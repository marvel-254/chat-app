import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Chats / Status bottom bar shared by the two home surfaces.
class HomeNavBar extends StatelessWidget {
  const HomeNavBar({super.key, required this.index});

  /// 0 = Chats, 1 = Status.
  final int index;

  static const _surface = Color(0xFF1E1F25);
  static const _primary = Color(0xFFD4FF00);
  static const _muted = Color(0xFFC5C9AC);

  @override
  Widget build(BuildContext context) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: _surface,
        elevation: 0,
        height: 68,
        indicatorColor: _primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _primary : _muted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? _primary : _muted, size: 22);
        }),
      ),
      child: NavigationBar(
        selectedIndex: index.clamp(0, 1),
        onDestinationSelected: (i) {
          if (i == index) return;
          if (i == 0) context.go('/conversations');
          if (i == 1) context.go('/status');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.slow_motion_video_outlined),
            selectedIcon: Icon(Icons.slow_motion_video),
            label: 'Status',
          ),
        ],
      ),
    );
  }
}
