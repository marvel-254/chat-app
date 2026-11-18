import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/avatar_config.dart';

/// A lightweight "3D" digital avatar painted with Flutter primitives.
///
/// **Limitation:** this is not a real 3D mesh or scene (no `flutter_cube` /
/// filament dependency). Depth is faked with a radial-gradient sphere, a
/// specular highlight, rim light, a soft contact shadow and squash-and-stretch
/// motion, and the character is a floating head rather than a full body. That
/// keeps the widget dependency-free, rasterised on the GPU and cheap enough to
/// drop into a profile header.
class DigitalAvatar extends StatefulWidget {
  const DigitalAvatar({
    super.key,
    required this.config,
    this.size = 120,
    this.interactive = true,
    this.onReact,
  });

  final AvatarConfig config;

  /// Widget width and height in logical pixels.
  final double size;

  /// Whether tapping plays the reaction effect.
  final bool interactive;

  /// Optional callback fired alongside the built-in reaction animation.
  final VoidCallback? onReact;

  @override
  State<DigitalAvatar> createState() => _DigitalAvatarState();
}

class _DigitalAvatarState extends State<DigitalAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final AnimationController _react = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.config.animationsEnabled) _idle.repeat();
  }

  @override
  void didUpdateWidget(DigitalAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.config.animationsEnabled) {
      if (!_idle.isAnimating) _idle.repeat();
    } else if (_idle.isAnimating) {
      _idle.stop();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _react.dispose();
    super.dispose();
  }

  void _handleTap() {
    widget.onReact?.call();
    if (!widget.interactive) return;
    _react.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.interactive ? _handleTap : null,
      child: Semantics(
        label: 'Digital avatar',
        button: widget.interactive,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_idle, _react]),
              builder: (_, __) => CustomPaint(
                painter: _DigitalAvatarPainter(
                  config: widget.config,
                  idle: _idle.value,
                  react: _react.value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitalAvatarPainter extends CustomPainter {
  _DigitalAvatarPainter({
    required this.config,
    required this.idle,
    required this.react,
  });

  final AvatarConfig config;

  /// Looping 0..1 phase driving the idle bob, breathing and blink.
  final double idle;

  /// One-shot 0..1 phase driving the tap reaction.
  final double react;

  static const _faceDark = Color(0xFF15161C);
  static const _hardware = Color(0xFF292A2F);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final r = s * 0.30;

    final body = _parseHex(config.bodyHex);
    final aura = _parseHex(config.auraHex);
    final face = body.computeLuminance() > 0.45
        ? _faceDark
        : Colors.white.withValues(alpha: 0.92);

    final t = idle * 2 * math.pi;
    final bob = math.sin(t) * s * 0.012;
    final breath = 1 + math.sin(t + math.pi / 2) * 0.012;
    final pulse = react < 1 ? math.sin(react * math.pi) : 0.0;

    canvas.save();
    canvas.translate(center.dx, center.dy + bob);
    canvas.scale(breath * (1 + pulse * 0.09));
    canvas.translate(-center.dx, -center.dy);

    _drawAura(canvas, center, r, aura);
    _drawContactShadow(canvas, center, r);

    final headPath = _headPath(center, r);
    // The halo sits behind the head so it never covers the ears or face.
    if (config.accessory == 'halo') _drawHalo(canvas, center, r);
    final headPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.38, -0.46),
        radius: 1.35,
        colors: [
          _lerp(body, Colors.white, 0.42),
          body,
          _lerp(body, Colors.black, 0.42),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r * 1.35));
    canvas.drawPath(headPath, headPaint);

    _drawRimLight(canvas, center, r, body);
    _drawSpecular(canvas, center, r);
    if (config.preset == 'robot') _drawRobotDetails(canvas, center, r, face);

    _drawCheeks(canvas, center, r, body);

    final eyes = <Offset>[
      Offset(center.dx - r * 0.36, center.dy - r * 0.08),
      Offset(center.dx + r * 0.36, center.dy - r * 0.08),
    ];
    if (config.accessory != 'shades') {
      _drawEyes(canvas, center, r, eyes, face);
      _drawBrows(canvas, center, r, eyes, face);
    }
    _drawMouth(canvas, center, r, face);
    _drawAccessory(canvas, center, r, eyes, aura, face);

    canvas.restore();

    if (react > 0 && react < 1) {
      _drawReactionParticles(canvas, center, r, s);
    }
  }

  // -----------------------------------------------------------------------
  // Head silhouette
  // -----------------------------------------------------------------------

  Path _headPath(Offset c, double r) {
    switch (config.preset) {
      case 'robot':
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: r * 1.78, height: r * 1.62),
            Radius.circular(r * 0.34),
          ));
      case 'cat':
        final head = Path()..addOval(Rect.fromCircle(center: c, radius: r));
        const signs = [-1.0, 1.0];
        for (final sign in signs) {
          final ear = Path()
            ..moveTo(c.dx + sign * r * 0.88, c.dy - r * 0.40)
            ..lineTo(c.dx + sign * r * 0.74, c.dy - r * 1.30)
            ..lineTo(c.dx + sign * r * 0.10, c.dy - r * 0.78)
            ..close();
          head.addPath(ear, Offset.zero);
        }
        return head;
      case 'buddy':
        return Path()
          ..addOval(Rect.fromCenter(
              center: c, width: r * 2.02, height: r * 1.92));
      default:
        return Path()..addOval(Rect.fromCircle(center: c, radius: r));
    }
  }

  // -----------------------------------------------------------------------
  // Lighting
  // -----------------------------------------------------------------------

  void _drawAura(Canvas canvas, Offset c, double r, Color aura) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          aura.withValues(alpha: 0.34),
          aura.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.9));
    canvas.drawCircle(c, r * 1.9, paint);
  }

  void _drawHalo(Canvas canvas, Offset c, double r) {
    final rect = Rect.fromCenter(
        center: Offset(c.dx, c.dy - r * 1.10), width: r * 1.28, height: r * 0.34);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.08
        ..color = const Color(0xFFFFD966).withValues(alpha: 0.95)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..color = Colors.white.withValues(alpha: 0.8),
    );
  }

  void _drawContactShadow(Canvas canvas, Offset c, double r) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx, c.dy + r * 1.24), width: r * 1.5, height: r * 0.26),
      paint,
    );
  }

  void _drawRimLight(Canvas canvas, Offset c, double r, Color body) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09
      ..strokeCap = StrokeCap.round
      ..color = _lerp(body, Colors.white, 0.5).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.90),
      math.pi * 0.22,
      math.pi * 0.46,
      false,
      paint,
    );
  }

  void _drawSpecular(Canvas canvas, Offset c, double r) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(c.dx - r * 0.34, c.dy - r * 0.44),
          width: r * 0.52,
          height: r * 0.30),
      paint,
    );
  }

  void _drawRobotDetails(Canvas canvas, Offset c, double r, Color face) {
    // The antenna is skipped when an accessory already owns the top of the
    // head (cap, halo, headphones band).
    final topTaken = config.accessory == 'cap' ||
        config.accessory == 'halo' ||
        config.accessory == 'headphones';
    if (!topTaken) {
      final antenna = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = _hardware
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(c.dx, c.dy - r * 0.82),
          Offset(c.dx, c.dy - r * 1.14), antenna);
      canvas.drawCircle(Offset(c.dx, c.dy - r * 1.20), r * 0.10,
          Paint()..color = _hardware);
    }

    // Ear bolts
    final bolt = Paint()..color = _hardware;
    canvas.drawCircle(Offset(c.dx - r * 0.92, c.dy), r * 0.10, bolt);
    canvas.drawCircle(Offset(c.dx + r * 0.92, c.dy), r * 0.10, bolt);

    // Mouth grille accent
    canvas.drawLine(
      Offset(c.dx - r * 0.20, c.dy + r * 0.52),
      Offset(c.dx + r * 0.20, c.dy + r * 0.52),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.045
        ..color = face.withValues(alpha: 0.55)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawCheeks(Canvas canvas, Offset c, double r, Color body) {
    if (config.expression != 'happy' &&
        config.expression != 'wink' &&
        config.expression != 'surprised') {
      return;
    }
    final paint = Paint()
      ..color = const Color(0xFFFF7AAC).withValues(alpha: 0.34)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset(c.dx - r * 0.54, c.dy + r * 0.22), r * 0.13, paint);
    canvas.drawCircle(Offset(c.dx + r * 0.54, c.dy + r * 0.22), r * 0.13, paint);
  }

  // -----------------------------------------------------------------------
  // Face
  // -----------------------------------------------------------------------

  double get _blink {
    // Blink during the first 8% of every 4s idle cycle.
    const start = 0.0;
    const end = 0.08;
    if (idle <= start || idle >= end) return 1.0;
    final p = (idle - start) / (end - start);
    return 1 - math.sin(p * math.pi);
  }

  void _drawEyes(
      Canvas canvas, Offset c, double r, List<Offset> eyes, Color face) {
    final open = _blink;
    final er = r * 0.11;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.075
      ..strokeCap = StrokeCap.round
      ..color = face;

    for (var i = 0; i < eyes.length; i++) {
      final eye = eyes[i];
      switch (config.expression) {
        case 'happy':
          canvas.drawArc(
            Rect.fromCenter(center: eye, width: er * 2.5, height: er * 2.5),
            math.pi,
            math.pi,
            false,
            stroke,
          );
          break;
        case 'wink':
          if (i == 0) {
            _drawOpenEye(canvas, eye, er * open, face);
          } else {
            canvas.drawArc(
              Rect.fromCenter(center: eye, width: er * 2.5, height: er * 2.5),
              math.pi,
              math.pi,
              false,
              stroke,
            );
          }
          break;
        case 'cool':
          canvas.drawLine(
            Offset(eye.dx - er * 1.2, eye.dy - er * 0.2),
            Offset(eye.dx + er * 1.2, eye.dy - er * 0.2),
            stroke,
          );
          canvas.drawArc(
            Rect.fromCenter(
                center: Offset(eye.dx, eye.dy + er * 0.2),
                width: er * 2.4,
                height: er * 2.4),
            0,
            math.pi,
            false,
            stroke,
          );
          break;
        case 'surprised':
          _drawOpenEye(canvas, eye, er * 1.45, face);
          break;
        default:
          _drawOpenEye(canvas, eye, er * open, face);
      }
    }
  }

  void _drawOpenEye(Canvas canvas, Offset eye, double radius, Color face) {
    if (radius <= 0.4) return;
    canvas.drawOval(
      Rect.fromCenter(center: eye, width: radius * 2, height: radius * 2),
      Paint()..color = face,
    );
    canvas.drawCircle(
      Offset(eye.dx - radius * 0.32, eye.dy - radius * 0.34),
      radius * 0.26,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  void _drawBrows(
      Canvas canvas, Offset c, double r, List<Offset> eyes, Color face) {
    final er = r * 0.11;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.055
      ..strokeCap = StrokeCap.round
      ..color = face;
    switch (config.expression) {
      case 'surprised':
        for (final eye in eyes) {
          canvas.drawLine(
            Offset(eye.dx - er * 1.2, eye.dy - r * 0.34),
            Offset(eye.dx + er * 1.2, eye.dy - r * 0.38),
            paint,
          );
        }
        break;
      case 'cool':
        canvas.drawLine(
          Offset(eyes[0].dx - er * 1.2, eyes[0].dy - r * 0.26),
          Offset(eyes[0].dx + er * 1.2, eyes[0].dy - r * 0.20),
          paint,
        );
        canvas.drawLine(
          Offset(eyes[1].dx - er * 1.2, eyes[1].dy - r * 0.20),
          Offset(eyes[1].dx + er * 1.2, eyes[1].dy - r * 0.26),
          paint,
        );
        break;
      default:
        break;
    }
  }

  void _drawMouth(Canvas canvas, Offset c, double r, Color face) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round
      ..color = face;
    switch (config.expression) {
      case 'surprised':
        canvas.drawCircle(
            Offset(c.dx, c.dy + r * 0.40), r * 0.10, Paint()..color = face);
        break;
      case 'happy':
      case 'wink':
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(c.dx, c.dy + r * 0.28), width: r * 0.52, height: r * 0.52),
          0,
          math.pi,
          false,
          paint,
        );
        break;
      case 'cool':
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(c.dx + r * 0.04, c.dy + r * 0.30),
              width: r * 0.44,
              height: r * 0.44),
          math.pi * 0.15,
          math.pi * 0.5,
          false,
          paint,
        );
        break;
      default:
        canvas.drawLine(
          Offset(c.dx - r * 0.15, c.dy + r * 0.38),
          Offset(c.dx + r * 0.15, c.dy + r * 0.38),
          paint,
        );
    }
  }

  // -----------------------------------------------------------------------
  // Accessories
  // -----------------------------------------------------------------------

  void _drawAccessory(Canvas canvas, Offset c, double r, List<Offset> eyes,
      Color aura, Color face) {
    final er = r * 0.11;
    switch (config.accessory) {
      case 'glasses':
        final frame = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.05
          ..strokeCap = StrokeCap.round
          ..color = face;
        for (final eye in eyes) {
          canvas.drawCircle(eye, er * 1.75, Paint()..color = Colors.white.withValues(alpha: 0.07));
          canvas.drawCircle(eye, er * 1.75, frame);
        }
        canvas.drawLine(
          Offset(eyes[0].dx + er * 1.75, eyes[0].dy),
          Offset(eyes[1].dx - er * 1.75, eyes[1].dy),
          frame,
        );
        canvas.drawLine(
          Offset(eyes[0].dx - er * 1.75, eyes[0].dy),
          Offset(c.dx - r * 0.94, c.dy - r * 0.14),
          frame,
        );
        canvas.drawLine(
          Offset(eyes[1].dx + er * 1.75, eyes[1].dy),
          Offset(c.dx + r * 0.94, c.dy - r * 0.14),
          frame,
        );
        break;
      case 'shades':
        final lens = Paint()..color = const Color(0xFF101116).withValues(alpha: 0.94);
        final glint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.045
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.35);
        for (final eye in eyes) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: eye, width: er * 3.5, height: er * 2.7),
              Radius.circular(er * 0.7),
            ),
            lens,
          );
          canvas.drawLine(
            Offset(eye.dx - er * 0.95, eye.dy + er * 0.65),
            Offset(eye.dx - er * 0.10, eye.dy - er * 0.75),
            glint,
          );
        }
        canvas.drawLine(
          Offset(eyes[0].dx + er * 1.75, eyes[0].dy - er * 0.2),
          Offset(eyes[1].dx - er * 1.75, eyes[1].dy - er * 0.2),
          lens..style = PaintingStyle.stroke..strokeWidth = r * 0.06,
        );
        break;
      case 'headphones':
        final band = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.14
          ..strokeCap = StrokeCap.round
          ..color = _hardware;
        canvas.drawArc(
          Rect.fromCenter(
              center: Offset(c.dx, c.dy - r * 0.12),
              width: r * 2.14,
              height: r * 2.14),
          math.pi * 1.06,
          math.pi * 0.88,
          false,
          band,
        );
        final cup = Paint()..color = _hardware;
        final cupEdge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04
          ..color = aura.withValues(alpha: 0.9);
        for (final sign in [-1.0, 1.0]) {
          final rect = Rect.fromCenter(
            center: Offset(c.dx + sign * r * 0.96, c.dy + r * 0.04),
            width: r * 0.34,
            height: r * 0.62,
          );
          canvas.drawRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(r * 0.16)), cup);
          canvas.drawRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(r * 0.16)), cupEdge);
        }
        break;
      case 'cap':
        final capPaint = Paint()..color = _lerp(aura, Colors.black, 0.08);
        final dome = Path()
          ..addArc(
            Rect.fromCenter(
                center: Offset(c.dx, c.dy - r * 0.34),
                width: r * 2.02,
                height: r * 2.02),
            math.pi,
            math.pi,
          )
          ..close();
        canvas.drawPath(dome, capPaint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(c.dx, c.dy - r * 0.32),
                width: r * 2.16,
                height: r * 0.24),
            Radius.circular(r * 0.12),
          ),
          capPaint,
        );
        canvas.drawCircle(
            Offset(c.dx, c.dy - r * 1.34), r * 0.09, capPaint);
        break;
      case 'halo':
        // Drawn before the head so it reads as a glow behind the avatar.
        break;
      default:
        break;
    }
  }

  // -----------------------------------------------------------------------
  // Reaction particles
  // -----------------------------------------------------------------------

  void _drawReactionParticles(Canvas canvas, Offset c, double r, double s) {
    const count = 7;
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + (i - (count - 1) / 2) * 0.34;
      final travel = r * (0.85 + 1.05 * react);
      final position = Offset(
        c.dx + math.cos(angle) * travel,
        c.dy + math.sin(angle) * travel - react * r * 0.35,
      );
      final alpha = (1 - react).clamp(0.0, 1.0);
      final fontSize = s * 0.11 * (0.85 + 0.35 * math.sin(react * math.pi));
      final painter = TextPainter(
        text: TextSpan(
          text: config.reaction,
          style: TextStyle(
            fontSize: fontSize,
            color: Color.fromRGBO(255, 255, 255, alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  // -----------------------------------------------------------------------

  static Color _parseHex(String value) {
    final normalized = value.startsWith('#') ? value.substring(1) : value;
    final parsed = int.tryParse('FF$normalized', radix: 16);
    return parsed == null ? const Color(0xFFD4FF00) : Color(parsed);
  }

  static Color _lerp(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  @override
  bool shouldRepaint(_DigitalAvatarPainter oldDelegate) =>
      oldDelegate.config != config ||
      oldDelegate.idle != idle ||
      oldDelegate.react != react;
}
