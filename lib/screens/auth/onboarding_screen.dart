import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart' as app_colors;

const _onboardingSeenKey = 'bro_onboarding_seen';
bool onboardingCompleted = false;

Future<void> loadOnboardingStatus() async {
  final preferences = await SharedPreferences.getInstance();
  onboardingCompleted = preferences.getBool(_onboardingSeenKey) ?? false;
}

Future<void> markOnboardingComplete() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(_onboardingSeenKey, true);
  onboardingCompleted = true;
}

/// Multi-page onboarding with smooth page transitions and staggered entrance animations.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  bool _continuing = false;
  late final PageController _pageController;
  late final AnimationController _ambientController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _pageController.addListener(() {
      if (_pageController.page != null) {
        final page = _pageController.page!.round();
        if (page != _currentPage) {
          setState(() => _currentPage = page);
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_continuing) return;
    setState(() => _continuing = true);
    try {
      await markOnboardingComplete();
    } catch (_) {
      // Keep the first-run path usable if local persistence is unavailable.
    }
    if (mounted) context.go('/login');
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _continue();
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 760;
    return Scaffold(
      backgroundColor: app_colors.P.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Ambient animated background glow
            AnimatedBuilder(
              animation: _ambientController,
              builder: (context, child) {
                final t = _ambientController.value;
                return Positioned.fill(
                  child: CustomPaint(
                    painter: _AmbientGlowPainter(
                      phase: t * math.pi * 2,
                      color: app_colors.P.primary,
                    ),
                  ),
                );
              },
            ),
            Center(
              child: PageView(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                children: [
                  _OnboardingPage(
                    title: 'For the people\nwho feel like home.',
                    subtitle:
                        'A calmer corner of your phone for your favorite conversations.',
                    artwork: const _ConversationArtwork(),
                    compact: compact,
                  ),
                  _OnboardingPage(
                    title: 'Your circle.\nYour rules.',
                    subtitle:
                        'Share moments with the people who matter most — no noise, no strangers.',
                    artwork: const _CircleArtwork(),
                    compact: compact,
                  ),
                  _OnboardingPage(
                    title: 'Private.\nInstant. Yours.',
                    subtitle:
                        'Messages that arrive fast, stay secure, and feel like you.',
                    artwork: const _PrivacyArtwork(),
                    compact: compact,
                  ),
                ],
              ),
            ),
            // Bottom controls overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Page indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          3,
                          (i) => Container(
                            width: _currentPage == i ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: _currentPage == i
                                  ? app_colors.P.primary
                                  : app_colors.P.primary
                                      .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Action button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _continuing ? null : _nextPage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: app_colors.P.primary,
                            foregroundColor: app_colors.P.darkOnAccent,
                            disabledBackgroundColor:
                                app_colors.P.primary.withValues(alpha: 0.7),
                            shape: const StadiumBorder(),
                            elevation: 0,
                            animationDuration:
                                const Duration(milliseconds: 200),
                          ),
                          child: _continuing
                              ? const SizedBox(
                                  width: 21,
                                  height: 21,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.3,
                                    color: app_colors.P.darkOnAccent,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _currentPage < 2
                                          ? 'Next'
                                          : 'Get started',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    Icon(
                                      _currentPage < 2
                                          ? Icons.arrow_forward_rounded
                                          : Icons.rocket_launch_rounded,
                                      size: 20,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 13),
                      const Center(
                        child: Text(
                          'FREE TO USE     ·     NO ADS',
                          style: TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Top wordmark overlay
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _Wordmark(),
                      TextButton(
                        onPressed: _continue,
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated ambient background glow that shifts subtly
class _AmbientGlowPainter extends CustomPainter {
  _AmbientGlowPainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.6, size.height * 0.35);
    final radius = math.max(size.width, size.height) * 0.45;

    // Slowly orbiting glow
    final offsetX = math.sin(phase) * size.width * 0.1;
    final offsetY = math.cos(phase * 0.7) * size.height * 0.08;
    final adjustedCenter = center + Offset(offsetX, offsetY);

    final gradient = RadialGradient(
      center: Alignment.center,
      radius: 1.0,
      colors: [
        color.withValues(alpha: 0.06),
        color.withValues(alpha: 0.02),
        Colors.transparent,
      ],
      stops: const [0, 0.5, 1],
    );

    canvas.drawCircle(
      adjustedCenter,
      radius,
      Paint()..shader = gradient.createShader(
        Rect.fromCircle(center: adjustedCenter, radius: radius),
      ),
    );
  }

  @override
  bool shouldRepaint(_AmbientGlowPainter oldDelegate) {
    return phase != oldDelegate.phase;
  }
}

/// A single onboarding page with staggered entrance animations.
class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.artwork,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final Widget artwork;
  final bool compact;

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeTitle;
  late final Animation<double> _fadeSubtitle;
  late final Animation<double> _fadeArtwork;
  late final Animation<double> _slideTitle;
  late final Animation<double> _slideSubtitle;
  late final Animation<double> _slideArtwork;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Staggered entrance: title → subtitle → artwork
    _fadeTitle = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3)),
    );
    _slideTitle = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3)),
    );

    _fadeSubtitle = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.45)),
    );
    _slideSubtitle = Tween<double>(begin: 25, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.45)),
    );

    _fadeArtwork = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.65)),
    );
    _slideArtwork = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.65)),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 120, 24, 180),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Title with fade + slide
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeTitle.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideTitle.value),
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: app_colors.P.text,
                        fontSize: 42,
                        height: 0.99,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.8,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 13),
            // Subtitle with fade + slide
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeSubtitle.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideSubtitle.value),
                    child: Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: app_colors.P.muted,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: widget.compact ? 16 : 28),
            // Artwork with fade + slide
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeArtwork.value,
                  child: Transform.translate(
                    offset: Offset(0, _slideArtwork.value),
                    child: widget.artwork,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: -0.15,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: app_colors.P.primary,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: app_colors.P.primary.withValues(alpha: 0.22),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'BRO',
          style: TextStyle(
            color: app_colors.P.text,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

/// A quiet little conversation vignette composed entirely from Flutter widgets.
/// It deliberately uses no avatar, raster artwork, or animation.
class _ConversationArtwork extends StatelessWidget {
  const _ConversationArtwork();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 4,
            right: 12,
            width: 246,
            height: 246,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: app_colors.P.primary.withValues(alpha: 0.13),
                ),
                gradient: RadialGradient(
                  colors: [
                    app_colors.P.primary.withValues(alpha: 0.10),
                    app_colors.P.primary.withValues(alpha: 0.015),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          Positioned(
            top: 20,
            left: 4,
            width: 248,
            child: Transform.rotate(
              angle: -0.045,
              child: const _MessageTile(
                label: 'THE LITTLE THINGS',
                message: 'Made it home. That was exactly the reset I needed.',
                time: '8:41 PM',
                color: Color(0xFF22252A),
                textColor: app_colors.P.text,
                labelColor: app_colors.P.muted,
              ),
            ),
          ),
          Positioned(
            top: 119,
            right: 2,
            width: 220,
            child: Transform.rotate(
              angle: 0.035,
              child: const _MessageTile(
                label: 'JUST YOU TWO',
                message: 'Same here. Let’s do it again soon.',
                time: '8:42 PM · READ',
                color: Color(0xFF394521),
                textColor: Color(0xFFF1F5E4),
                labelColor: app_colors.P.primary,
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 28,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF17191E),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: app_colors.P.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 19,
                      color: app_colors.P.darkOnAccent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A voice note, when typing is too much.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: app_colors.P.text,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '0:12  ·  TAP TO LISTEN',
                          style: TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 8,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.play_arrow_rounded,
                      color: app_colors.P.primary, size: 21),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.label,
    required this.message,
    required this.time,
    required this.color,
    required this.textColor,
    required this.labelColor,
  });

  final String label;
  final String message;
  final String time;
  final Color color;
  final Color textColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            time,
            style: TextStyle(
              color: labelColor.withValues(alpha: 0.8),
              fontSize: 8,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Artwork for the "Your circle. Your rules." onboarding page.
/// Shows a group of avatars orbiting a central connection point.
class _CircleArtwork extends StatefulWidget {
  const _CircleArtwork();

  @override
  State<_CircleArtwork> createState() => _CircleArtworkState();
}

class _CircleArtworkState extends State<_CircleArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Central glow
          Positioned(
            top: 4,
            right: 12,
            width: 246,
            height: 246,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: app_colors.P.primary.withValues(alpha: 0.10),
                ),
                gradient: RadialGradient(
                  colors: [
                    app_colors.P.primary.withValues(alpha: 0.08),
                    app_colors.P.primary.withValues(alpha: 0.015),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          // Orbiting avatars
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Stack(
                children: [
                  // Connection lines from center
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CircleLinesPainter(
                        phase: t * math.pi * 2,
                        color: app_colors.P.primary,
                      ),
                    ),
                  ),
                  // Center node
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 110,
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: app_colors.P.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: app_colors.P.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: app_colors.P.primary.withValues(alpha: 0.2),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.group_rounded,
                          size: 26,
                          color: app_colors.P.primary,
                        ),
                      ),
                    ),
                  ),
                  // Orbiting member avatars
                  for (int i = 0; i < 5; i++)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _OrbitAvatar(
                          index: i,
                          total: 5,
                          phase: t * math.pi * 2,
                          radius: 90,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          // Bottom label card
          Positioned(
            left: 20,
            right: 28,
            bottom: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF17191E),
                borderRadius: BorderRadius.circular(17),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: app_colors.P.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.people_rounded,
                      size: 19,
                      color: app_colors.P.darkOnAccent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Circles keep your people close.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: app_colors.P.text,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '5 MEMBERS  ·  ACTIVE NOW',
                          style: TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 8,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: app_colors.P.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: app_colors.P.success,
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitAvatar extends StatelessWidget {
  const _OrbitAvatar({
    required this.index,
    required this.total,
    required this.phase,
    required this.radius,
  });

  final int index;
  final int total;
  final double phase;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final angle = (index / total) * math.pi * 2 + phase;
    final x = math.cos(angle) * radius;
    final y = math.sin(angle) * radius * 0.5; // elliptical orbit
    final depth = math.sin(angle);
    final scale = 0.85 + depth * 0.15;

    const colors = [
      Color(0xFFD4FF00),
      Color(0xFF8DB7FF),
      Color(0xFFFF8D8D),
      Color(0xFF8DFFB7),
      Color(0xFFFFB78D),
    ];

    return Transform.translate(
      offset: Offset(x, y),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors[index].withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: colors[index].withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: colors[index].withValues(alpha: 0.15),
                blurRadius: 12,
              ),
            ],
          ),
          child: Icon(
            Icons.person_rounded,
            size: 20,
            color: colors[index],
          ),
        ),
      ),
    );
  }
}

class _CircleLinesPainter extends CustomPainter {
  _CircleLinesPainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 10);
    const radius = 90.0;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 5; i++) {
      final angle = (i / 5) * math.pi * 2 + phase;
      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius * 0.5;
      canvas.drawLine(center, Offset(x, y), paint);
    }
  }

  @override
  bool shouldRepaint(_CircleLinesPainter oldDelegate) =>
      phase != oldDelegate.phase;
}

/// Artwork for the "Private. Instant. Yours." onboarding page.
/// Shows a shield with checkmark and floating security elements.
class _PrivacyArtwork extends StatefulWidget {
  const _PrivacyArtwork();

  @override
  State<_PrivacyArtwork> createState() => _PrivacyArtworkState();
}

class _PrivacyArtworkState extends State<_PrivacyArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background glow
          Positioned(
            top: 4,
            right: 12,
            width: 246,
            height: 246,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: app_colors.P.primary.withValues(alpha: 0.10),
                ),
                gradient: RadialGradient(
                  colors: [
                    app_colors.P.primary.withValues(alpha: 0.08),
                    app_colors.P.primary.withValues(alpha: 0.015),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.55, 1],
                ),
              ),
            ),
          ),
          // Central shield
          Positioned(
            left: 0,
            right: 0,
            top: 30,
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final t = _controller.value;
                  final breathe = 1.0 + math.sin(t * math.pi * 2) * 0.03;
                  return Transform.scale(
                    scale: breathe,
                    child: Container(
                      width: 100,
                      height: 116,
                      decoration: BoxDecoration(
                        color: app_colors.P.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: app_colors.P.primary.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                app_colors.P.primary.withValues(alpha: 0.15),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 48,
                        color: app_colors.P.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Floating feature badges
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Stack(
                children: [
                  // Lock badge - top left
                  Positioned(
                    left: 16,
                    top: 80 + math.sin(t * math.pi * 2 + 0.5) * 8,
                    child: _FeatureBadge(
                      icon: Icons.lock_rounded,
                      label: 'ENCRYPTED',
                      color: app_colors.P.primary,
                    ),
                  ),
                  // Speed badge - top right
                  Positioned(
                    right: 12,
                    top: 60 + math.sin(t * math.pi * 2 + 1.5) * 10,
                    child: _FeatureBadge(
                      icon: Icons.bolt_rounded,
                      label: 'INSTANT',
                      color: const Color(0xFF8DB7FF),
                    ),
                  ),
                  // Check badge - bottom left
                  Positioned(
                    left: 30,
                    bottom: 70 + math.sin(t * math.pi * 2 + 2.5) * 7,
                    child: _FeatureBadge(
                      icon: Icons.check_circle_rounded,
                      label: 'VERIFIED',
                      color: app_colors.P.success,
                    ),
                  ),
                ],
              );
            },
          ),
          // Bottom info card
          Positioned(
            left: 20,
            right: 28,
            bottom: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF17191E),
                borderRadius: BorderRadius.circular(17),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: app_colors.P.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      size: 19,
                      color: app_colors.P.success,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'End-to-end encrypted by default.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: app_colors.P.text,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'YOUR DATA  ·  YOUR CONTROL',
                          style: TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 8,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.security_rounded,
                    color: app_colors.P.success,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: app_colors.P.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
