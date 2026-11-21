import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import '../../../ui/hero_motion.dart';
import '../../../ui/motion.dart';

/// The 3D props that anchor the auth screens — exactly one per screen.
///
/// Renders are original BRO art (see `assets/images/ASSET_SOURCES.md`): matte
/// charcoal with volt-lime accents, keyed from a chroma field so they sit
/// straight on the auth backdrop without a card or a frame around them.
abstract final class AuthArt {
  /// Sign in / sign up.
  static const mascot = 'assets/images/prop_mascot.webp';

  /// Onboarding 1 — the people you talk to.
  static const chat = 'assets/images/prop_chat.webp';

  /// Onboarding 2 — your circle.
  static const circle = 'assets/images/prop_circle.webp';

  /// Onboarding 3 — quick and personal.
  static const bolt = 'assets/images/prop_bolt.webp';

  /// width / height for each render, so a prop keeps its proportions.
  static const mascotAspect = 560 / 1003;
  static const chatAspect = 520 / 417;
  static const circleAspect = 510 / 462;
  static const boltAspect = 300 / 507;
}

/// A single 3D prop standing in an auth scene.
///
/// One object, one light, one shadow — no orbiting collage. It idles with a
/// slow float and a whisper of yaw, leans with the pointer, and settles into a
/// still pose when the OS asks for reduced motion.
class AuthProp extends StatefulWidget {
  const AuthProp({
    super.key,
    required this.asset,
    required this.height,
    required this.aspectRatio,
    this.animate = true,
    this.floatAmplitude = 5,
    this.yawAmplitude = 0.05,
    this.parallax = 10,
    this.glow = 0.9,
    this.shadow = true,
  });

  /// Asset path — one of the [AuthArt] constants.
  final String asset;

  /// Rendered height; the width follows [aspectRatio].
  final double height;

  /// Intrinsic width / height of [asset].
  final double aspectRatio;

  /// Enables the idle float and pointer lean. Reduce motion always wins.
  final bool animate;

  /// Vertical travel of the idle float, in logical pixels.
  final double floatAmplitude;

  /// Yaw sway of the idle float, in radians.
  final double yawAmplitude;

  /// Travel per unit of pointer shift, in logical pixels.
  final double parallax;

  /// Strength of the soft volt halo behind the prop (0 disables it).
  final double glow;

  /// Whether to paint a contact shadow at the prop's base.
  final bool shadow;

  @override
  State<AuthProp> createState() => _AuthPropState();
}

class _AuthPropState extends State<AuthProp> with SingleTickerProviderStateMixin {
  static const _idleDuration = Duration(seconds: 11);

  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: _idleDuration,
  );

  bool _motionOn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant AuthProp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncMotion();
  }

  void _syncMotion() {
    final allow = widget.animate && !reduceMotionOf(context);
    if (allow == _motionOn) return;
    _motionOn = allow;
    if (allow) {
      if (!_idle.isAnimating) _idle.repeat();
    } else if (_idle.isAnimating) {
      _idle.stop();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.height * widget.aspectRatio;
    final phase = _motionOn ? _idle.value : 0.0;
    final turn = phase * math.pi * 2;
    final bob = math.sin(turn) * widget.floatAmplitude;
    final yaw = math.sin(turn + 0.9) * widget.yawAmplitude;

    return SizedBox(
      width: width,
      height: widget.height,
      child: HeroParallax(
        enabled: _motionOn,
        builder: (context, shift) {
          final dx = shift.dx * widget.parallax;
          final dy = shift.dy * widget.parallax * 0.5;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              if (widget.glow > 0)
                Positioned(
                  left: -width * 0.45,
                  right: -width * 0.45,
                  top: -widget.height * 0.08,
                  bottom: -widget.height * 0.02,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              app_colors.P.primary
                                  .withValues(alpha: 0.09 * widget.glow),
                              const Color(0xFF292A35)
                                  .withValues(alpha: 0.10 * widget.glow),
                              Colors.transparent,
                            ],
                            stops: const [0, 0.55, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.shadow)
                Positioned(
                  left: width * 0.18 + dx * 0.35,
                  right: width * 0.18 - dx * 0.35,
                  bottom: 0,
                  height: math.max(10.0, widget.height * 0.06),
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.black.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(dx, bob + dy),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(yaw)
                    ..rotateX(math.sin(turn + 2.1) * 0.012),
                  child: SizedBox(
                    width: width,
                    height: widget.height,
                    child: ExcludeSemantics(
                      child: Image.asset(
                        widget.asset,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomCenter,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
