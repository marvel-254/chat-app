/// Expressive motion primitives shared by the auth hero.
///
/// House rules for this file:
///
///  * every primitive honours the OS "reduce motion" switch — callers pass
///    [HeroParallax.enabled] / drive [HeroEntrance.animation] with a rest value
///    of `1` when motion is off;
///  * no primitive owns a repeating [AnimationController] — a scene drives one
///    loop controller and feeds its value in, so the whole composition stays on
///    a single timeline (and tests can settle);
///  * poses are pure functions of a `0..1` phase, so the choreography can be
///    asserted without pumping a single frame.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Builds a subtree from the current, smoothed pointer shift.
///
/// [shift] is normalised: `(-1, -1)` is the top-left of the stage, `(0, 0)` the
/// centre and `(1, 1)` the bottom-right.
typedef HeroShiftBuilder = Widget Function(BuildContext context, Offset shift);

/// Pointer-driven parallax for hero artwork.
///
/// Tracks hover on desktop/web and drags or taps on touch, smoothing the shift
/// with an implicit animation so the scene leans instead of snapping. When
/// [enabled] is false it never subscribes to pointers and always reports a
/// zero shift, which is exactly what reduce-motion users should see.
class HeroParallax extends StatefulWidget {
  const HeroParallax({
    super.key,
    required this.builder,
    this.enabled = true,
    this.smoothing = const Duration(milliseconds: 420),
  });

  final HeroShiftBuilder builder;

  /// Whether pointer tracking is active (false under reduce motion).
  final bool enabled;

  /// Duration of the easing between two pointer positions.
  final Duration smoothing;

  @override
  State<HeroParallax> createState() => _HeroParallaxState();
}

class _HeroParallaxState extends State<HeroParallax> {
  Offset _target = Offset.zero;

  static const _deadZone = 0.012;

  void _pointAt(Offset local, Size size) {
    if (!widget.enabled) return;
    if (!size.width.isFinite || !size.height.isFinite) return;
    if (size.width <= 0 || size.height <= 0) return;

    final dx = ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0).toDouble();
    final dy = ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0).toDouble();
    final next = Offset(dx, dy);
    if ((next - _target).distance < _deadZone) return;
    setState(() => _target = next);
  }

  void _reset() {
    if (_target == Offset.zero) return;
    setState(() => _target = Offset.zero);
  }

  @override
  void didUpdateWidget(covariant HeroParallax oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _target != Offset.zero) {
      _target = Offset.zero;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 372,
        );
        final shift = widget.enabled ? _target : Offset.zero;
        return MouseRegion(
          onHover: (event) => _pointAt(event.localPosition, size),
          onExit: (_) => _reset(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _pointAt(event.localPosition, size),
            onPointerMove: (event) => _pointAt(event.localPosition, size),
            child: TweenAnimationBuilder<Offset>(
              tween: Tween<Offset>(begin: Offset.zero, end: shift),
              duration: widget.smoothing,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) =>
                  widget.builder(context, widget.enabled ? value : Offset.zero),
            ),
          ),
        );
      },
    );
  }
}

/// A resolved position on the hero's elliptical orbit.
///
/// [depth] is `-1` when the prop is at the far side of the loop and `1` at the
/// near side, so callers can split props into "behind the mascot" and "in front
/// of the mascot" without recomputing the trigonometry.
@immutable
class HeroOrbitPose {
  const HeroOrbitPose({
    required this.offset,
    required this.depth,
    required this.scale,
    required this.yaw,
    required this.roll,
  });

  /// Displacement from the orbit centre, in logical pixels.
  final Offset offset;

  /// `-1` (far) … `1` (near).
  final double depth;

  /// Depth-based scale between the configured minimum and maximum.
  final double scale;

  /// Y-axis rotation in radians — the fake-3D tumble.
  final double yaw;

  /// Z-axis rotation in radians — the lean into the loop.
  final double roll;

  /// Resolves a pose for [phase] (`0..1`, one full loop per unit).
  ///
  /// [turns] lets a prop orbit faster than the hero loop, [angleOffset] staggers
  /// props around the same path, and the radius pair shapes the ellipse.
  static HeroOrbitPose at({
    required double phase,
    double angleOffset = 0,
    double turns = 1,
    double radiusX = 30,
    double radiusY = 10,
    double minScale = 0.84,
    double maxScale = 1.06,
    double yawAmplitude = 0.22,
    double rollAmplitude = 0.1,
  }) {
    final angle = phase * math.pi * 2 * turns + angleOffset;
    final depth = math.sin(angle);
    final nearness = (depth + 1) / 2;
    return HeroOrbitPose(
      offset: Offset(math.cos(angle) * radiusX, depth * radiusY),
      depth: depth,
      scale: minScale + (maxScale - minScale) * nearness,
      yaw: math.cos(angle) * yawAmplitude,
      roll: math.sin(angle * 0.5) * rollAmplitude,
    );
  }

  /// True when the prop should paint behind the mascot.
  bool get isBehind => depth < 0;

  /// Paint order key: far props first.
  double get sortKey => depth;

  @override
  String toString() =>
      'HeroOrbitPose(offset: $offset, depth: ${depth.toStringAsFixed(2)}, '
      'scale: ${scale.toStringAsFixed(2)})';
}

/// Staggered fade + rise + settle entrance driven by a parent animation.
///
/// [index] orders the element inside the scene (0 is first). The element is
/// fully visible when [animation] reaches `1`, which is also the rest pose used
/// for reduce motion, so a static build is just `value = 1`.
///
/// Stateful on purpose: the derived [CurvedAnimation] registers a status
/// listener on the parent controller, so it must be created once and disposed
/// rather than rebuilt on every frame of the scene.
class HeroEntrance extends StatefulWidget {
  const HeroEntrance({
    super.key,
    required this.animation,
    required this.child,
    this.index = 0,
    this.stagger = 0.08,
    this.length = 0.55,
    this.slide = 0.12,
    this.scaleFrom = 0.94,
    this.curve = Curves.easeOutCubic,
  });

  /// The element being staged.
  final Widget child;

  /// Intro progress, `0` (hidden) … `1` (rest).
  final Animation<double> animation;

  /// Position in the stagger sequence.
  final int index;

  /// Delay between consecutive elements, as a fraction of the intro.
  final double stagger;

  /// Portion of the intro this element spends animating.
  final double length;

  /// Vertical travel, as a fraction of the child's height.
  final double slide;

  /// Scale the element grows from.
  final double scaleFrom;

  final Curve curve;

  @override
  State<HeroEntrance> createState() => _HeroEntranceState();
}

class _HeroEntranceState extends State<HeroEntrance> {
  late CurvedAnimation _curve;
  late Animation<Offset> _slide;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _rebuildAnimations();
  }

  @override
  void didUpdateWidget(covariant HeroEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.index != widget.index ||
        oldWidget.stagger != widget.stagger ||
        oldWidget.length != widget.length ||
        oldWidget.slide != widget.slide ||
        oldWidget.scaleFrom != widget.scaleFrom ||
        oldWidget.curve != widget.curve) {
      _curve.dispose();
      _rebuildAnimations();
    }
  }

  void _rebuildAnimations() {
    final start = (widget.index * widget.stagger)
        .clamp(0.0, 1.0 - widget.length)
        .toDouble();
    _curve = CurvedAnimation(
      parent: widget.animation,
      curve: Interval(start, start + widget.length, curve: widget.curve),
    );
    _slide = Tween<Offset>(
      begin: Offset(0.0, widget.slide),
      end: Offset.zero,
    ).animate(_curve);
    _scale = Tween<double>(begin: widget.scaleFrom, end: 1.0).animate(_curve);
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
