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

/// Image-free intro shown once before the existing welcome/sign-in screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _continuing = false;

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

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 760;
    return Scaffold(
      backgroundColor: app_colors.P.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, compact ? 14 : 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Wordmark(),
                  SizedBox(height: compact ? 26 : 38),
                  const Text(
                    'MESSAGING, MADE PERSONAL',
                    style: TextStyle(
                      color: app_colors.P.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'For the people\nwho feel like home.',
                    style: TextStyle(
                      color: app_colors.P.text,
                      fontSize: 42,
                      height: 0.99,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.8,
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'A calmer corner of your phone for your favorite conversations.',
                    style: TextStyle(
                      color: app_colors.P.muted,
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 22),
                  const _ConversationArtwork(),
                  SizedBox(height: compact ? 6 : 15),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed: _continuing ? null : _continue,
                      style: FilledButton.styleFrom(
                        backgroundColor: app_colors.P.primary,
                        foregroundColor: app_colors.P.darkOnAccent,
                        disabledBackgroundColor:
                            app_colors.P.primary.withValues(alpha: 0.7),
                        shape: const StadiumBorder(),
                        elevation: 0,
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
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Get started',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(width: 9),
                                Icon(Icons.arrow_forward_rounded, size: 20),
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
