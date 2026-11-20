import 'package:flutter/material.dart';

import '../theme/app_colors.dart' as app_colors;

/// Shared atmospheric backdrop for BRO's auth surfaces.
///
/// Layered radial volt glows over the near-black base, a whisper of film
/// grain, and a soft vignette to pull the eye toward the center. Fully
/// static — no controllers — so it stays smooth on every device and is a
/// no-op for reduce-motion.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, this.child});

  /// Content painted above the atmosphere (typically a [SafeArea] + form).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: app_colors.P.bg),
        // Volt aurora — top right
        Positioned(
          top: -190,
          right: -170,
          width: 380,
          height: 380,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  app_colors.P.primary.withValues(alpha: 0.17),
                  app_colors.P.primary.withValues(alpha: 0.05),
                  Colors.transparent,
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        // Cool olive bloom — bottom left
        Positioned(
          bottom: -210,
          left: -190,
          width: 420,
          height: 420,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF3A4024).withValues(alpha: 0.55),
                  const Color(0xFF23241B).withValues(alpha: 0.35),
                  Colors.transparent,
                ],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ),
        // Film grain
        Positioned.fill(
          child: Opacity(
            opacity: 0.55,
            child: Image.asset(
              'assets/images/noise_tile.png',
              repeat: ImageRepeat.repeat,
              filterQuality: FilterQuality.none,
              gaplessPlayback: true,
            ),
          ),
        ),
        // Center-weighted vignette
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.15, -0.35),
                radius: 1.25,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.46),
                ],
                stops: const [0.52, 0.8, 1.0],
              ),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}
