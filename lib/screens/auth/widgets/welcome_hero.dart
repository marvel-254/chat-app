import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import '../../../theme/app_text.dart';
import '../../../ui/hero_motion.dart';
import '../../../ui/motion.dart';

/// Asset paths for the regenerated hero props.
///
/// The artwork is original BRO art (see `assets/images/ASSET_SOURCES.md`):
/// charcoal surfaces with volt-lime accents, rendered on a chroma field so the
/// transparent cut-outs composite straight onto the auth backdrop.
abstract final class HeroArt {
  static const mascot = 'assets/images/hero_mascot.webp';
  static const ball = 'assets/images/hero_ball.webp';
  static const gamepad = 'assets/images/hero_gamepad.webp';
  static const supercar = 'assets/images/hero_supercar.webp';

  /// Intrinsic aspect ratio of [mascot] (560 × 1003).
  static const mascotAspect = 560 / 1003;
}

/// A small, expressive 3D-style welcome scene for the sign-in screen.
///
/// The mascot travels an elliptical depth path while three props orbit her on
/// their own, slower loops and swap between the background and foreground as
/// they pass. Pointer movement leans the whole stage (parallax), and the copy
/// settles in on a staggered intro. Everything is driven by two controllers —
/// one repeating loop, one entrance — and the scene collapses to a static rest
/// pose when the OS asks for reduced motion.
class WelcomeHero extends StatefulWidget {
  const WelcomeHero({
    super.key,
    required this.isSignUp,
    this.animate = true,
    this.showEyebrow = true,
    this.showFeatureCards = true,
  });

  final bool isSignUp;

  /// Enables the loop, entrance and parallax. Reduce-motion always wins.
  final bool animate;

  final bool showEyebrow;
  final bool showFeatureCards;

  @override
  State<WelcomeHero> createState() => _WelcomeHeroState();
}

class _WelcomeHeroState extends State<WelcomeHero>
    with TickerProviderStateMixin {
  static const _stageHeight = 372.0;
  static const _loopDuration = Duration(seconds: 16);
  static const _introDuration = Duration(milliseconds: 1250);

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: _loopDuration,
  );
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _introDuration,
  );
  late final Listenable _timeline = Listenable.merge([_loop, _intro]);

  /// Rest pose used when motion is off: intro at 1, loop at 0.
  static const Animation<double> _rest = AlwaysStoppedAnimation<double>(1.0);

  bool _motionOn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant WelcomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _syncMotion();
  }

  /// Starts/stops the timelines without writing controller values during the
  /// build phase (the build reads a rest pose instead).
  void _syncMotion() {
    final allow = widget.animate && !reduceMotionOf(context);
    if (allow == _motionOn) return;
    _motionOn = allow;
    if (allow) {
      if (!_loop.isAnimating) _loop.repeat();
      if (!_intro.isAnimating && _intro.value < 1) _intro.forward();
    } else {
      if (_loop.isAnimating) _loop.stop();
      if (_intro.isAnimating) _intro.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  String get _heading =>
      widget.isSignUp ? 'Your people.\nYour place.' : 'Good to see you, Bro.';

  String get _subheading => widget.isSignUp
      ? 'Make room for the conversations that matter.'
      : 'All your conversations, right here.';

  @override
  Widget build(BuildContext context) {
    final intro = _motionOn ? _intro : _rest;
    return SizedBox(
      height: _stageHeight,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 350;
          return HeroParallax(
            enabled: _motionOn,
            builder: (context, shift) => AnimatedBuilder(
              animation: _timeline,
              builder: (context, _) => _buildStage(
                compact: compact,
                stageWidth: constraints.maxWidth,
                phase: _motionOn ? _loop.value : 0.0,
                shift: shift,
                intro: intro,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStage({
    required bool compact,
    required double stageWidth,
    required double phase,
    required Offset shift,
    required Animation<double> intro,
  }) {
    // Guard against unbounded/degenerate constraints in tiny layouts.
    final resolvedWidth =
        stageWidth.isFinite && stageWidth > 200 ? stageWidth : 360.0;
    final centerX = resolvedWidth / 2;

    final mascotHeight = compact ? 238.0 : 258.0;
    final mascotWidth = mascotHeight * HeroArt.mascotAspect;

    final mascotPose = HeroOrbitPose.at(
      phase: phase,
      radiusX: compact ? 20 : 30,
      radiusY: 8,
      minScale: 0.95,
      maxScale: 1.05,
      yawAmplitude: 0.3,
      rollAmplitude: 0.02,
    );
    final bob = math.sin(phase * math.pi * 4) * 3.5;
    final breathe = (math.sin(phase * math.pi * 2) + 1) / 2; // 0..1

    final props = <_PlacedProp>[];
    for (final spec in _propSpecs) {
      final pose = HeroOrbitPose.at(
        phase: phase,
        angleOffset: spec.angleOffset,
        turns: spec.turns,
        radiusX: spec.radiusX * (compact ? 0.74 : 1),
        radiusY: spec.radiusY,
        minScale: 0.78,
        maxScale: 1.06,
        yawAmplitude: 0.34,
        rollAmplitude: 0.16,
      );
      props.add(_PlacedProp(spec: spec, pose: pose));
    }
    props.sort((a, b) => a.pose.sortKey.compareTo(b.pose.sortKey));
    final behind = props.where((p) => p.pose.isBehind).toList(growable: false);
    final front = props.where((p) => !p.pose.isBehind).toList(growable: false);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Atmosphere: breathing halo + two counter-rotating orbit rings ──
        Positioned(
          left: centerX - 176,
          top: 60,
          width: 352,
          height: 310,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: HeroEntrance(
                animation: intro,
                index: 0,
                scaleFrom: 0.9,
                child: Transform.scale(
                  scale: 0.97 + breathe * 0.05,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(180),
                      gradient: RadialGradient(
                        colors: [
                          app_colors.P.primary
                              .withValues(alpha: 0.10 + breathe * 0.045),
                          const Color(0xFF292A35).withValues(alpha: 0.16),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.55, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _ring(
          centerX: centerX,
          phase: phase,
          intro: intro,
          size: compact ? 210 : 236,
          top: 104,
          turns: 0.11,
          alpha: 0.16,
          glow: 26,
          baseAngle: -0.16,
        ),
        _ring(
          centerX: centerX,
          phase: phase,
          intro: intro,
          size: compact ? 172 : 194,
          top: 124,
          turns: -0.07,
          alpha: 0.10,
          glow: 16,
          baseAngle: 0.2,
        ),

        // ── Props on the far side of the loop, behind the mascot ──────────
        for (final entry in behind)
          _prop(entry,
              centerX: centerX,
              compact: compact,
              shift: shift,
              intro: intro),

        // ── The mascot ───────────────────────────────────────────────────
        Positioned(
          left: centerX - mascotWidth / 2 + mascotPose.offset.dx + shift.dx * -10,
          bottom: 6 + mascotPose.offset.dy + bob + shift.dy * -6,
          width: mascotWidth,
          height: mascotHeight,
          child: IgnorePointer(
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0016)
                ..rotateY(mascotPose.yaw)
                ..rotateX(math.cos(phase * math.pi * 2) * 0.02)
                ..scale(mascotPose.scale),
              child: HeroEntrance(
                animation: intro,
                index: 3,
                slide: 0.16,
                scaleFrom: 0.88,
                child: ExcludeSemantics(
                  child: Image.asset(
                    HeroArt.mascot,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Contact shadow: shrinks and fades as she lifts on the near side.
        Positioned(
          left: centerX - 74 + mascotPose.offset.dx * 0.55,
          bottom: 4 - mascotPose.offset.dy * 0.3,
          width: 148,
          height: 22,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: 0.58 - mascotPose.depth * 0.12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.62),
                        Colors.black.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Props on the near side of the loop, in front of the mascot ────
        for (final entry in front)
          _prop(entry,
              centerX: centerX,
              compact: compact,
              shift: shift,
              intro: intro),

        // ── Copy ─────────────────────────────────────────────────────────
        Positioned(
          top: 4,
          left: 0,
          right: 0,
          child: Column(
            children: [
              if (widget.showEyebrow)
                HeroEntrance(
                  animation: intro,
                  index: 1,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          app_colors.P.surfaceHigh.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: app_colors.P.border.withValues(alpha: 0.8),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle,
                            size: 7, color: app_colors.P.primary),
                        SizedBox(width: 7),
                        Text(
                          'BRO  ·  YOUR PEOPLE, CLOSER',
                          style: AppText.eyebrow,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              HeroEntrance(
                animation: intro,
                index: 2,
                slide: 0.18,
                child: Text(
                  _heading,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppText.heroTitle
                      .copyWith(fontSize: compact ? 25 : 28),
                ),
              ),
              const SizedBox(height: 6),
              HeroEntrance(
                animation: intro,
                index: 3,
                slide: 0.2,
                child: Text(
                  _subheading,
                  textAlign: TextAlign.center,
                  style: AppText.subtitle,
                ),
              ),
            ],
          ),
        ),

        if (widget.showFeatureCards) ...[
          Positioned(
            left: compact ? 1 : 8,
            top: 181 + math.sin(phase * math.pi * 2 + 1) * 7,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: HeroEntrance(
                  animation: intro,
                  index: 5,
                  slide: 0.3,
                  child: const _WelcomeFloatCard(
                    icon: Icons.lock_rounded,
                    title: 'Private by design',
                    detail: 'Just your circle',
                    accent: app_colors.P.primary,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: compact ? 0 : 8,
            top: 132 + math.sin(phase * math.pi * 2 + 2.2) * 8,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: HeroEntrance(
                  animation: intro,
                  index: 6,
                  slide: 0.3,
                  child: const _WelcomeFloatCard(
                    icon: Icons.bolt_rounded,
                    title: 'Always in sync',
                    detail: 'Pick up anywhere',
                    accent: Color(0xFF8DB7FF),
                  ),
                ),
              ),
            ),
          ),
        ],

        // Pulsing message bead.
        Positioned(
          right: resolvedWidth * 0.18,
          bottom: 22 + math.sin(phase * math.pi * 2 + 3) * 5,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: HeroEntrance(
                animation: intro,
                index: 7,
                child: Transform.scale(
                  scale: 1 + breathe * 0.07,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: app_colors.P.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: app_colors.P.primary.withValues(alpha: 0.35),
                          blurRadius: 18 + breathe * 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.forum_rounded,
                        size: 17, color: app_colors.P.darkOnAccent),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _ring({
    required double centerX,
    required double phase,
    required Animation<double> intro,
    required double size,
    required double top,
    required double turns,
    required double alpha,
    required double glow,
    required double baseAngle,
  }) {
    return Positioned(
      left: centerX - size / 2,
      top: top,
      width: size,
      height: size,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: HeroEntrance(
            animation: intro,
            index: 1,
            scaleFrom: 0.86,
            child: Transform.rotate(
              angle: baseAngle + phase * math.pi * 2 * turns,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size / 2),
                  border: Border.all(
                    color: app_colors.P.primary.withValues(alpha: alpha),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: app_colors.P.primary.withValues(alpha: 0.06),
                      blurRadius: glow,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _prop(
    _PlacedProp entry, {
    required double centerX,
    required bool compact,
    required Offset shift,
    required Animation<double> intro,
  }) {
    final spec = entry.spec;
    final pose = entry.pose;
    final lateral = spec.centerX * (compact ? 0.82 : 1);
    return Positioned(
      left: centerX + lateral + pose.offset.dx + shift.dx * spec.parallax -
          spec.width / 2,
      bottom: spec.centerY + pose.offset.dy + shift.dy * spec.parallax * 0.6 -
          spec.height / 2,
      width: spec.width,
      height: spec.height,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0022)
              ..rotateY(pose.yaw)
              ..rotateZ(pose.roll)
              ..scale(pose.scale),
            child: HeroEntrance(
              animation: intro,
              index: 4,
              slide: 0.24,
              scaleFrom: 0.7,
              child: Opacity(
                opacity: 0.82 + (pose.depth + 1) / 2 * 0.18,
                child: Image.asset(
                  spec.asset,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One orbiting prop: size, path and the parallax weight it reacts with.
class _PropSpec {
  const _PropSpec({
    required this.asset,
    required this.width,
    required this.height,
    required this.centerX,
    required this.centerY,
    required this.angleOffset,
    required this.turns,
    required this.radiusX,
    required this.radiusY,
    required this.parallax,
  });

  final String asset;
  final double width;
  final double height;

  /// Offset of the orbit centre from the stage centre, in logical pixels.
  final double centerX;

  /// Orbit centre measured from the bottom of the stage.
  final double centerY;

  final double angleOffset;

  /// Loop speed relative to the hero loop.
  final double turns;

  final double radiusX;
  final double radiusY;

  /// How far this prop travels per unit of pointer shift.
  final double parallax;
}

class _PlacedProp {
  const _PlacedProp({required this.spec, required this.pose});

  final _PropSpec spec;
  final HeroOrbitPose pose;
}

/// Props orbit the mascot's torso: offset from the centre, their own stagger
/// angle and a slightly slower loop so the scene never looks uniform.
const _propSpecs = <_PropSpec>[
  _PropSpec(
    asset: HeroArt.ball,
    width: 62,
    height: 62,
    centerX: -110,
    centerY: 165,
    angleOffset: 0.5,
    turns: 1.0,
    radiusX: 40,
    radiusY: 18,
    parallax: 24,
  ),
  _PropSpec(
    asset: HeroArt.gamepad,
    width: 96,
    height: 64,
    centerX: 108,
    centerY: 130,
    angleOffset: 3.1,
    turns: 1.0,
    radiusX: 38,
    radiusY: 24,
    parallax: 18,
  ),
  _PropSpec(
    asset: HeroArt.supercar,
    width: 140,
    height: 78,
    centerX: -100,
    centerY: 55,
    angleOffset: 4.6,
    turns: 0.92,
    radiusX: 85,
    radiusY: 22,
    parallax: 30,
  ),
];

class _WelcomeFloatCard extends StatelessWidget {
  const _WelcomeFloatCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: app_colors.P.surfaceHigh.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(color: accent.withValues(alpha: 0.09), blurRadius: 20),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: accent),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                    color: app_colors.P.text,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 2),
              Text(detail,
                  style: const TextStyle(
                    color: app_colors.P.muted,
                    fontSize: 8,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
