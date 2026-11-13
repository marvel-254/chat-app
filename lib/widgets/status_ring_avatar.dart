import 'package:flutter/material.dart';

/// Lime ring around an avatar when that person has an active status.
class StatusRingAvatar extends StatelessWidget {
  const StatusRingAvatar({
    super.key,
    required this.child,
    required this.size,
    this.active = true,
    this.onTap,
  });

  final Widget child;
  final double size;
  final bool active;
  final VoidCallback? onTap;

  static const _primary = Color(0xFFD4FF00);
  static const _muted = Color(0xFF444932);

  @override
  Widget build(BuildContext context) {
    final ring = Container(
      width: size + 8,
      height: size + 8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? _primary : _muted,
          width: 2.2,
        ),
      ),
      child: child,
    );
    if (onTap == null) return ring;
    return GestureDetector(onTap: onTap, child: ring);
  }
}
