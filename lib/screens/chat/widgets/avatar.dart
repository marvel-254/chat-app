import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart' as app_colors;

class Avatar extends StatelessWidget {
  const Avatar(
      {super.key,
      required this.name,
      this.size = 44,
      this.url,
      this.showOnlineDot = false});
  final String name;
  final double size;
  final String? url;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [app_colors.bg, app_colors.surfaceHigh],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: url == null || url!.isEmpty
          ? Text(name.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600))
          : ClipOval(
              child: Image.network(url!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(name.toUpperCase(),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: size * 0.4,
                              fontWeight: FontWeight.w600))))),
    );

    if (!showOnlineDot) return avatar;

    // Dot size scales with avatar: ~22% of avatar diameter, min 8, max 14.
    final dotSize = (size * 0.22).clamp(8.0, 14.0);
    final borderWidth = (dotSize * 0.22).clamp(1.5, 2.5);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: app_colors.P.success,
              shape: BoxShape.circle,
              border: Border.all(color: app_colors.P.bg, width: borderWidth),
              boxShadow: [
                BoxShadow(
                  color: app_colors.P.success.withValues(alpha: 0.45),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


