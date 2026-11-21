import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart' as app_colors;
import '../../../theme/app_text.dart';
import '../../../ui/hero_motion.dart';
import '../../../ui/motion.dart';
import 'auth_prop.dart';

/// The sign-in hero: the welcome copy, and (optionally) one 3D prop under it.
///
/// It is deliberately quiet — a single figure, a soft halo and a grounded
/// shadow, instead of a collage of objects orbiting the character. The copy
/// settles in on a short stagger and the prop idles with the faintest float
/// (see [AuthProp]); reduce motion renders the still pose.
class WelcomeHero extends StatefulWidget {
  const WelcomeHero({
    super.key,
    required this.isSignUp,
    this.animate = true,
    this.showEyebrow = true,
    this.showProp = true,
  });

  final bool isSignUp;

  /// Enables the entrance and the prop's idle motion. Reduce motion always wins.
  final bool animate;

  final bool showEyebrow;

  /// Whether to stand the prop under the copy. The login screen turns this off
  /// and paints [AuthPropBackdrop] behind the whole page instead, so the copy
  /// and the art stop competing for the same column.
  final bool showProp;

  @override
  State<WelcomeHero> createState() => _WelcomeHeroState();
}

class _WelcomeHeroState extends State<WelcomeHero>
    with SingleTickerProviderStateMixin {
  static const _stageHeight = 380.0;
  static const _introDuration = Duration(milliseconds: 1100);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _introDuration,
  );

  /// Rest pose used when motion is off: the intro is complete.
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

  /// Starts/stops the intro without writing controller values during build.
  void _syncMotion() {
    final allow = widget.animate && !reduceMotionOf(context);
    if (allow == _motionOn) return;
    _motionOn = allow;
    if (allow) {
      if (!_intro.isAnimating && _intro.value < 1) _intro.forward();
    } else if (_intro.isAnimating) {
      _intro.stop();
    }
  }

  @override
  void dispose() {
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
    final body = LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 350;
          // The copy sizes itself; the prop takes whatever room is left, so a
          // two-line sign-up headline can never collide with her.
          final maxPropHeight = compact ? 236.0 : 268.0;
          return Column(
            mainAxisSize:
                widget.showProp ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Column(
                children: [
                  if (widget.showEyebrow)
                    HeroEntrance(
                      animation: intro,
                      index: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
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
                    index: 1,
                    slide: 0.16,
                    child: Text(
                      _heading,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style:
                          AppText.heroTitle.copyWith(fontSize: compact ? 25 : 28),
                    ),
                  ),
                  const SizedBox(height: 6),
                  HeroEntrance(
                    animation: intro,
                    index: 2,
                    slide: 0.2,
                    child: Text(
                      _subheading,
                      textAlign: TextAlign.center,
                      style: AppText.subtitle,
                    ),
                  ),
                ],
              ),
              if (widget.showProp)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, propBox) {
                    final height = math.min(maxPropHeight, propBox.maxHeight);
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: HeroEntrance(
                        animation: intro,
                        index: 3,
                        slide: 0.14,
                        scaleFrom: 0.92,
                        child: AuthProp(
                          asset: AuthArt.mascot,
                          height: height,
                          aspectRatio: AuthArt.mascotAspect,
                          animate: widget.animate,
                          floatAmplitude: 4,
                          yawAmplitude: 0.05,
                          parallax: 8,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      );
    if (!widget.showProp) return body;
    return SizedBox(
      height: _stageHeight,
      width: double.infinity,
      child: body,
    );
  }
}
