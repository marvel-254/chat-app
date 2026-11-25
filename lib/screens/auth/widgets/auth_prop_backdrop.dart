import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import 'auth_prop.dart';

/// The auth prop, blown up to the background of the whole page.
///
/// The login screen still shows exactly one prop — it just stands behind the
/// page instead of under the copy. On wide layouts she bleeds off the right and
/// bottom edges, mirrored so she faces back into the form; on phones she sits
/// across the top. A scrim over her keeps the headline and the fields legible,
/// so the art never fights the UI.
///
/// Purely decorative: no semantics, no hit testing, no motion.
class AuthPropBackdrop extends StatelessWidget {
  const AuthPropBackdrop({super.key});

  static const _wide = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      app_colors.P.bg,
      Color(0xFA121318),
      Color(0xE0121318),
      Color(0x73121318),
      Color(0x0D121318),
      Color(0x00121318),
    ],
    stops: [0, 0.34, 0.52, 0.72, 0.92, 1],
  );

  // Phones put the copy straight over her, so the veil starts high and the
  // figure is knocked back to a backdrop instead of a subject.
  static const _tall = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x8C121318),
      Color(0xA3121318),
      Color(0xEB121318),
      app_colors.P.bg,
    ],
    stops: [0, 0.38, 0.64, 0.78],
  );

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= app_colors.desktopBreakpoint;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: wide ? Alignment.bottomRight : Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: wide ? 1.04 : 0.62,
                  child: AspectRatio(
                    aspectRatio: AuthArt.mascotAspect,
                    child: Transform.flip(
                      flipX: wide,
                      child: Opacity(
                        opacity: wide ? 1 : 0.8,
                        child: Image.asset(
                          AuthArt.mascot,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(gradient: wide ? _wide : _tall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
