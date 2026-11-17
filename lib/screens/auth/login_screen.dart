import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../ui/errors.dart';
import '../../ui/states.dart';
import '../../app_constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _isSignUp = false;
  String _guideTarget = 'email';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (!email.contains('@') || !email.contains('.')) {
        throw "That email doesn't look quite right.";
      }
      if (password.length < 6) {
        throw 'Use at least 6 characters for your password.';
      }
      if (_isSignUp) {
        final username = _username.text.trim();
        if (username.length < 3 ||
            !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
          throw 'Usernames need at least 3 letters, numbers, dots, dashes, or underscores.';
        }
        final res = await Supa.signUp(email, password, username);
        // Supabase may require email confirmation before sign-in is allowed.
        // If no session was created, the user must confirm their email first.
        if (res.session == null) {
          if (mounted) {
            context.go('/confirm', extra: email);
          }
          return;
        }
      } else {
        await Supa.signIn(email, password);
      }
      if (mounted) {
        context.go('/conversations');
      }
    } catch (e) {
      if (e is AuthApiException && e.code == 'email_not_confirmed') {
        // The account exists but the email hasn't been confirmed yet (#49).
        // Route to the confirmation screen (which can resend the email)
        // instead of surfacing a raw exception.
        if (mounted) context.go('/confirm', extra: _email.text.trim());
        return;
      }
      if (e is AuthRetryableFetchException) {
        if (mounted) {
          setState(() => _error = friendlyErrorMessage(e));
        }
        return;
      }
      if (e is AuthException) {
        if (mounted) {
          setState(() => _error = friendlyErrorMessage(
                e,
                fallback: "We couldn't sign you in. Please try again.",
              ));
        }
        return;
      }
      if (e is StateError) {
        if (mounted) setState(() => _error = friendlyErrorMessage(e));
        return;
      }
      if (e is PostgrestException) {
        if (mounted) {
          setState(() => _error = friendlyErrorMessage(
                e,
                fallback:
                    "We couldn't finish creating your account. Please try again.",
              ));
        }
        return;
      }
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = app_colors.P.primary;
    final darkOnAccent = app_colors.P.darkOnAccent;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: app_colors.bg),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WelcomeHero(isSignUp: _isSignUp),
                    const SizedBox(height: 28),

                    // Segmented Sign In / Create toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: app_colors.P.surfaceLow,
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: app_colors.P.border, width: 1),
                      ),
                      child: Row(
                        children: [
                          for (final entry in [
                            (_isSignUp ? 'Sign In' : 'Sign In', false),
                            (
                              _isSignUp ? 'Create Account' : 'Create Account',
                              true
                            ),
                          ])
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isSignUp = entry.$2;
                                  _guideTarget =
                                      entry.$2 ? 'username' : 'email';
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _isSignUp == entry.$2
                                        ? accent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(36),
                                    boxShadow: _isSignUp == entry.$2
                                        ? [
                                            BoxShadow(
                                                color: accent.withValues(
                                                    alpha: 0.3),
                                                blurRadius: 16)
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(entry.$1,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _isSignUp == entry.$2
                                              ? darkOnAccent
                                              : app_colors.P.muted,
                                        )),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) SoftErrorBanner(message: _error!),

                    // Fields
                    if (_isSignUp) ...[
                      _AuthField(
                        controller: _username,
                        label: 'What They Call You',
                        prefix: Icons.badge_outlined,
                        suffix: Icons.check_circle,
                        suffixColor: accent,
                        placeholder: 'alex_vance',
                        textInputAction: TextInputAction.next,
                        isGuideTarget: _guideTarget == 'username',
                        onFocus: () =>
                            setState(() => _guideTarget = 'username'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _AuthField(
                      controller: _email,
                      label: 'Email',
                      prefix: Icons.alternate_email_outlined,
                      placeholder: 'you@bro.network',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      isGuideTarget: _guideTarget == 'email',
                      onFocus: () => setState(() => _guideTarget = 'email'),
                    ),
                    const SizedBox(height: 16),
                    _AuthField(
                      controller: _password,
                      label: 'Secret Code',
                      prefix: Icons.lock_outline,
                      placeholder: '••••••••',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      isGuideTarget: _guideTarget == 'password',
                      onFocus: () => setState(() => _guideTarget = 'password'),
                    ),
                    const SizedBox(height: 24),

                    // CTA
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: GestureDetector(
                        onTap: _loading ? null : _submit,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.35),
                                  blurRadius: 22,
                                  spreadRadius: 1)
                            ],
                          ),
                          alignment: Alignment.center,
                          child: _loading
                              ? BroSpinner(
                                  size: 22,
                                  strokeWidth: 2.5,
                                  color: darkOnAccent,
                                )
                              : Text(_isSignUp ? 'Create Account' : 'Sign In',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: darkOnAccent,
                                      letterSpacing: 0.3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _guideTarget = _isSignUp ? 'username' : 'email';
                      }),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 14, color: app_colors.P.muted),
                          children: [
                            TextSpan(
                                text: _isSignUp
                                    ? 'Already in the crew? '
                                    : 'Need an account? ',
                                style:
                                    const TextStyle(color: app_colors.P.muted)),
                            TextSpan(
                                text: _isSignUp
                                    ? 'Sign In, Bro'
                                    : 'Claim Your Tag',
                                style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('By stepping in, you rep the Bro Code.',
                        style: TextStyle(
                            fontSize: 11, color: app_colors.P.muted)),
                    if (buildNumber.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('BRO · build $buildNumber',
                          style: const TextStyle(
                              fontSize: 11, color: app_colors.P.muted)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small, animated 3D-style welcome scene for the sign-in screen.
/// Local transparent renders sit in a Flutter-drawn, animated depth scene.
class WelcomeHero extends StatefulWidget {
  const WelcomeHero({
    super.key,
    required this.isSignUp,
    this.animate = true,
    this.showEyebrow = true,
    this.showFeatureCards = true,
  });
  final bool isSignUp;
  final bool animate;
  final bool showEyebrow;
  final bool showFeatureCards;

  @override
  State<WelcomeHero> createState() => _WelcomeHeroState();
}

class _WelcomeHeroState extends State<WelcomeHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _motion.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WelcomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _motion.repeat();
      } else {
        _motion.stop();
        _motion.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 370,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 350;
          final artWidth = compact ? 218.0 : 250.0;
          final artHeight = compact ? 238.0 : 250.0;
          return AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final phase = _motion.value * math.pi * 2;
              // Move the character around an elliptical path: the changing
              // scale and perspective lean suggest near/far depth, while the
              // shifting shadow anchors her to the scene.
              final depth = math.cos(phase);
              final orbitX = math.sin(phase) * 28;
              final orbitY = depth * 7;
              final depthScale = 0.96 + depth * 0.055;
              final tilt = math.sin(phase) * 0.2;
              final heading = widget.isSignUp
                  ? 'Your people.\nYour place.'
                  : 'Good to see you, Bro.';
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Deep, softly-lit stage and orbit rings.
                  Positioned(
                    left: constraints.maxWidth * 0.12,
                    right: constraints.maxWidth * 0.12,
                    top: 62,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(180),
                        gradient: RadialGradient(
                          colors: [
                            app_colors.P.primary.withValues(alpha: 0.12),
                            const Color(0xFF292A35).withValues(alpha: 0.16),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: constraints.maxWidth * 0.19,
                    right: constraints.maxWidth * 0.19,
                    top: 109,
                    height: 205,
                    child: Transform.rotate(
                      angle: -0.16,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(110),
                          border: Border.all(
                            color: app_colors.P.primary.withValues(alpha: 0.17),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: app_colors.P.primary.withValues(alpha: 0.07),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        if (widget.showEyebrow) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: app_colors.P.surfaceHigh.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: app_colors.P.border.withValues(alpha: 0.8),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 7, color: app_colors.P.primary),
                                SizedBox(width: 7),
                                Text(
                                  'BRO  ·  YOUR PEOPLE, CLOSER',
                                  style: TextStyle(
                                    color: app_colors.P.muted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.05,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          heading,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: app_colors.P.text,
                            fontSize: compact ? 25 : 28,
                            height: 1.02,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.isSignUp
                              ? 'Make room for the conversations that matter.'
                              : 'All your conversations, right here.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // A few glossy 3D collectibles orbit the character.
                  Positioned(
                    left: (compact ? 7.0 : 18.0) + math.sin(phase + 0.4) * 5,
                    bottom: 88 + math.sin(phase + 0.9) * 8,
                    child: _OrbitBall(phase: phase),
                  ),
                  Positioned(
                    left: (compact ? 2.0 : 12.0) + math.sin(phase + 2.4) * 5,
                    bottom: 18 + math.sin(phase + 2.1) * 6,
                    child: _OrbitGamepad(phase: phase),
                  ),
                  Positioned(
                    right: (compact ? 0.0 : 7.0) + math.sin(phase + 1.1) * 7,
                    bottom: 67 + math.sin(phase + 1.6) * 7,
                    child: _OrbitSupercar(phase: phase),
                  ),
                  // A moving contact shadow gives her path a grounded depth cue.
                  Positioned(
                    left: (constraints.maxWidth - 154) / 2 + orbitX * 0.65,
                    bottom: 9 - orbitY * 0.25,
                    width: 154 * depthScale,
                    height: 22,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.58),
                            Colors.black.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // The character travels around the stage rather than staying
                  // pinned in place. Perspective, scale and lean sell the orbit.
                  Positioned(
                    bottom: 5 + orbitY,
                    left: 0,
                    right: 0,
                    height: artHeight,
                    child: Transform.translate(
                      offset: Offset(orbitX, 0),
                      child: Center(
                        child: SizedBox(
                          width: artWidth,
                          height: artHeight,
                          child: Transform.scale(
                            scale: depthScale,
                            alignment: Alignment.bottomCenter,
                            child: Transform(
                              alignment: Alignment.bottomCenter,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0015)
                                ..rotateY(tilt)
                                ..rotateX(math.cos(phase) * 0.018),
                              child: Semantics(
                                image: true,
                                label: 'BRO character moving around the welcome scene',
                                child: Image.asset(
                                  'assets/images/welcome_avatar_fullbody.png',
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.showFeatureCards) ...[
                    Positioned(
                      left: compact ? 1 : 8,
                      top: 181 + math.sin(phase + 1) * 7,
                      child: const _WelcomeFloatCard(
                        icon: Icons.lock_rounded,
                        title: 'Private by design',
                        detail: 'Just your circle',
                        accent: app_colors.P.primary,
                      ),
                    ),
                    Positioned(
                      right: compact ? 0 : 8,
                      top: 132 + math.sin(phase + 2.2) * 8,
                      child: const _WelcomeFloatCard(
                        icon: Icons.bolt_rounded,
                        title: 'Always in sync',
                        detail: 'Pick up anywhere',
                        accent: Color(0xFF8DB7FF),
                      ),
                    ),
                  ],
                  Positioned(
                    right: constraints.maxWidth * 0.18,
                    bottom: 22 + math.sin(phase + 3) * 5,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: app_colors.P.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: app_colors.P.primary.withValues(alpha: 0.35),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.forum_rounded,
                          size: 17, color: app_colors.P.darkOnAccent),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Downloaded transparent renders make the scene props real image assets.
class _OrbitBall extends StatelessWidget {
  const _OrbitBall({required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateY(-0.18 + math.sin(phase) * 0.34)
        ..rotateZ(-0.12 + math.cos(phase) * 0.22),
      child: Semantics(
        image: true,
        label: 'Glossy blue 3D soccer ball',
        child: Image.asset(
          'assets/images/welcome_3d_ball.webp',
          width: 54,
          height: 54,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _OrbitGamepad extends StatelessWidget {
  const _OrbitGamepad({required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateY(0.12 + math.sin(phase + 1.4) * 0.12)
        ..rotateZ(-0.15 + math.cos(phase + 1.4) * 0.06),
      child: Semantics(
        image: true,
        label: 'Black 3D game controller',
        child: Image.asset(
          'assets/images/welcome_3d_gamepad.png',
          width: 84,
          height: 58,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class _OrbitSupercar extends StatelessWidget {
  const _OrbitSupercar({required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Yellow Lamborghini supercar',
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateY(-0.1 + math.sin(phase + 1.8) * 0.12)
          ..rotateZ(-0.055),
        child: Image.asset(
          'assets/images/welcome_lamborghini.png',
          width: 128,
          height: 69,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

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
        color: app_colors.P.surface.withValues(alpha: 0.94),
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

/// Pill-shaped auth input matching the Electric Street design.
class _AuthField extends StatefulWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.prefix,
    required this.placeholder,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.suffixColor,
    this.isGuideTarget = false,
    this.onFocus,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefix;
  final String placeholder;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? suffix;
  final Color? suffixColor;
  final bool isGuideTarget;
  final VoidCallback? onFocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  late bool _obscured = widget.obscureText;

  @override
  void didUpdateWidget(covariant _AuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(widget.label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: app_colors.P.muted,
                  letterSpacing: 0.08)),
        ),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: app_colors.P.surfaceLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: widget.isGuideTarget ? app_colors.P.primary : app_colors.P.border,
              width: widget.isGuideTarget ? 1.5 : 1,
            ),
            boxShadow: widget.isGuideTarget
                ? [
                    BoxShadow(
                      color: app_colors.P.primary.withValues(alpha: 0.12),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: TextField(
            controller: widget.controller,
            obscureText: _obscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            onTap: widget.onFocus,
            style: const TextStyle(
                color: app_colors.P.text, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              prefixIcon: Icon(widget.prefix, color: app_colors.P.muted, size: 20),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              hintText: widget.placeholder,
              hintStyle: TextStyle(
                  color: app_colors.P.muted.withValues(alpha: 0.6)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide:
                    const BorderSide(color: app_colors.P.primary, width: 1.5),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              suffixIcon: widget.obscureText
                  ? IconButton(
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: app_colors.P.muted,
                        size: 20,
                      ),
                      tooltip:
                          _obscured ? 'Show password' : 'Hide password',
                      onPressed: () =>
                          setState(() => _obscured = !_obscured),
                    )
                  : (widget.suffix != null
                      ? Icon(widget.suffix,
                          color: widget.suffixColor ?? app_colors.P.muted,
                          size: 20)
                      : null),
            ),
          ),
        ),
      ],
    );
  }
}

