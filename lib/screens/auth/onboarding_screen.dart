import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart' as app_colors;
import '../../theme/app_text.dart';
import '../../ui/motion.dart';
import '../../ui/auth_backdrop.dart';
import 'widgets/auth_prop.dart';
import 'widgets/bro_wordmark.dart';

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

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _continuing = false;
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
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
      if (reduceMotionOf(context)) {
        _pageController.jumpToPage(_currentPage + 1);
        return;
      }
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
    final reduce = reduceMotionOf(context);
    return Scaffold(
      backgroundColor: app_colors.P.bg,
      body: AuthBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
            Center(
              child: PageView(
                controller: _pageController,
                physics: const ClampingScrollPhysics(),
                children: [
                  _OnboardingPage(
                    title: 'For the people\nwho feel like home.',
                    subtitle:
                        'A calmer corner of your phone for your favorite conversations.',
                    artwork: const _PropArtwork(
                      asset: AuthArt.chat,
                      aspectRatio: AuthArt.chatAspect,
                      height: 214,
                    ),
                  ),
                  _OnboardingPage(
                    title: 'Your circle.\nYour rules.',
                    subtitle:
                        'Share moments with the people who matter most — no noise, no strangers.',
                    artwork: const _PropArtwork(
                      asset: AuthArt.circle,
                      aspectRatio: AuthArt.circleAspect,
                      height: 232,
                    ),
                  ),
                  _OnboardingPage(
                    title: 'Fast. Personal.\nYours.',
                    subtitle:
                        'Messages for your circle — quick to deliver, quiet by default.',
                    artwork: const _PropArtwork(
                      asset: AuthArt.bolt,
                      aspectRatio: AuthArt.boltAspect,
                      height: 244,
                      shadow: false,
                    ),
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
                      // Page indicators (accessible buttons, 44px targets)
                      Semantics(
                        container: true,
                        label:
                            'Page ${_currentPage + 1} of 3',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            3,
                            (i) => Semantics(
                              button: true,
                              selected: _currentPage == i,
                              label: 'Go to page ${i + 1} of 3',
                              child: InkWell(
                                onTap: () {
                                  if (reduce) {
                                    _pageController.jumpToPage(i);
                                  } else {
                                    _pageController.animateToPage(
                                      i,
                                      duration:
                                          const Duration(milliseconds: 350),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(20),
                                hoverColor: app_colors.P.primary
                                    .withValues(alpha: 0.08),
                                focusColor: app_colors.P.primary
                                    .withValues(alpha: 0.15),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 18, horizontal: 8),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: _currentPage == i ? 20 : 8,
                                    height: 8,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 3),
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
                                      style: AppText.button,
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
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'Create an account or sign in · free, no ads',
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
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
                  const BroWordmark(),
                  TextButton(
                    onPressed: _continue,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      foregroundColor: app_colors.P.muted,
                    ),
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
      ),
    );
  }
}

/// A single onboarding page with staggered entrance animations.
class _OnboardingPage extends StatefulWidget {
  const _OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.artwork,
  });

  final String title;
  final String subtitle;
  final Widget artwork;

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

    // resolved in didChangeDependencies where MediaQuery is available
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 96, 20, 148),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                minHeight:
                    math.max(0, constraints.maxHeight - 96 - 148),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                            style: compact ? AppText.displayLG : AppText.displayXL,
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
                            style: AppText.body,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: compact ? 16 : 28),
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
          ),
        );
      },
    );
  }
}

/// The artwork slot for one onboarding page: a single 3D prop, centred.
class _PropArtwork extends StatelessWidget {
  const _PropArtwork({
    required this.asset,
    required this.aspectRatio,
    required this.height,
    this.shadow = true,
  });

  final String asset;
  final double aspectRatio;
  final double height;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
      width: double.infinity,
      child: Center(
        child: AuthProp(
          asset: asset,
          height: height,
          aspectRatio: aspectRatio,
          shadow: shadow,
          floatAmplitude: 5,
          parallax: 12,
        ),
      ),
    );
  }
}
