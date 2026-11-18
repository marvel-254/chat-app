import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Compact "Playing ..." line used in chat headers and conversation rows.
class GamePresenceTag extends StatelessWidget {
  const GamePresenceTag({
    super.key,
    required this.label,
    this.color,
    this.fontSize = 12,
  });

  final String label;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? P.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.sports_esports_outlined, size: fontSize + 3, color: tint),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tint,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
