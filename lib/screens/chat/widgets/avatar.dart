import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart' as app_colors;
import '../../../models/avatar_config.dart';
import '../../../widgets/digital_avatar.dart';

class Avatar extends StatelessWidget {
  const Avatar(
      {super.key,
      required this.name,
      this.size = 44,
      this.url,
      this.showOnlineDot = false,
      this.digitalConfig});
  final String name;
  final double size;
  final String? url;
  final bool showOnlineDot;
  final AvatarConfig? digitalConfig;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty ? '?' : name.trim().toUpperCase();
    final fallback = Center(
      child: Text(initials,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w600)),
    );
    final photo = url?.trim();
    final useDigital =
        digitalConfig?.enabled == true && (photo == null || photo.isEmpty);
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [app_colors.bg, app_colors.surfaceHigh],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: useDigital
          ? DigitalAvatar(
              config: digitalConfig!, size: size, interactive: false)
          : photo == null || photo.isEmpty
              ? fallback
              : Image.network(
                  photo,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  frameBuilder: (_, child, frame, __) =>
                      frame == null ? fallback : child,
                  errorBuilder: (_, __, ___) => fallback,
                ),
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
