import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../ui/errors.dart';
import '../../ui/motion.dart';
import '../../ui/auth_backdrop.dart';
import '../../theme/app_text.dart';
import '../../app_constants.dart';
import 'auth_validation.dart';
import 'widgets/auth_controls.dart';
import 'widgets/bro_wordmark.dart';

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
  String? _notice;
  final Map<String, String?> _fieldErrors = {};

  void _clearFieldError(String field) {
    setState(() => _fieldErrors.remove(field));
  }

  void _switchMode(bool isSignUp) {
    setState(() {
      _isSignUp = isSignUp;
      _guideTarget = isSignUp ? 'username' : 'email';
      _error = null;
      _notice = null;
      _fieldErrors.clear();
    });
  }

  String? _validateForm() {
    final errors = <String, String?>{};
    final email = _email.text.trim();
    final password = _password.text;

    if (_isSignUp) {
      errors['username'] = validateUsername(_username.text);
    }
    errors['email'] = validateEmail(email);
    errors['password'] = validatePassword(password);
    errors.removeWhere((_, value) => value == null);

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return 'Please fix the highlighted fields.';
    return null;
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final validation = _validateForm();
      if (validation != null) {
        return; // inline errors already set; no banner needed
      }
      final email = _email.text.trim();
      final password = _password.text;
      if (_isSignUp) {
        final res = await Supa.signUp(email, password, _username.text.trim());
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

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    final emailError = validateEmail(email);
    if (emailError != null) {
      setState(() {
        _fieldErrors['email'] = emailError;
        _error = null;
        _notice = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
      _fieldErrors.remove('email');
    });
    try {
      await Supa.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => _notice =
            'Reset link sent to $email. Check your inbox to choose a new password.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback:
                  "We couldn't send the reset email just now. Please try again.",
            ));
      }
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

  String get _heading =>
      _isSignUp ? 'Your people.\nYour place.' : 'Good to see you, Bro.';

  String get _subheading => _isSignUp
      ? 'Make room for the conversations that matter.'
      : 'All your conversations, right here.';

  Widget _buildCompactHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BroWordmark(),
        const SizedBox(height: 14),
        Text(
          _heading,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: AppText.heroTitleCompact,
        ),
        const SizedBox(height: 6),
        Text(
          _subheading,
          textAlign: TextAlign.center,
          style: AppText.subtitle,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final isSignIn = !_isSignUp;
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Segmented Sign In / Create toggle
          AuthModeToggle(
            isSignUp: _isSignUp,
            onChanged: _switchMode,
          ),
          const SizedBox(height: 24),

          if (_error != null)
            Semantics(
              liveRegion: true,
              child: SoftErrorBanner(message: _error!),
            ),
          if (_notice != null)
            Semantics(liveRegion: true, child: AuthNoticeBanner(message: _notice!)),

          // Fields
          if (_isSignUp) ...[
            AuthTextField(
              controller: _username,
              label: 'What They Call You',
              prefix: Icons.badge_outlined,
              suffix: Icons.check_circle,
              suffixColor: app_colors.P.primary,
              placeholder: 'alex_vance',
              textInputAction: TextInputAction.next,
              isGuideTarget: _guideTarget == 'username',
              autofillHints: const [AutofillHints.newUsername],
              autocorrect: false,
              errorText: _fieldErrors['username'],
              onFocus: () {
                _clearFieldError('username');
                setState(() => _guideTarget = 'username');
              },
            ),
            const SizedBox(height: 16),
          ],
          AuthTextField(
            controller: _email,
            label: 'Email',
            prefix: Icons.alternate_email_outlined,
            placeholder: 'you@bro.network',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            isGuideTarget: _guideTarget == 'email',
            autofillHints:
                isSignIn ? const [AutofillHints.email] : const [AutofillHints.newUsername, AutofillHints.email],
            autocorrect: false,
            errorText: _fieldErrors['email'],
            onFocus: () {
              _clearFieldError('email');
              setState(() => _guideTarget = 'email');
            },
          ),
          const SizedBox(height: 16),
          AuthTextField(
            controller: _password,
            label: 'Password',
            prefix: Icons.lock_outline,
            placeholder: '••••••••',
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            isGuideTarget: _guideTarget == 'password',
            autofillHints: isSignIn
                ? const [AutofillHints.password]
                : const [AutofillHints.newPassword],
            errorText: _fieldErrors['password'],
            helperText: _isSignUp ? 'At least 6 characters.' : null,
            onFocus: () {
              _clearFieldError('password');
              setState(() => _guideTarget = 'password');
            },
          ),
          if (isSignIn) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading ? null : _forgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: app_colors.P.muted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 24),

          // CTA
          AuthPrimaryButton(
            key: const Key('auth-cta'),
            label: _isSignUp ? 'Create Account' : 'Sign In',
            loading: _loading,
            onPressed: _submit,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loading
                ? null
                : () => _switchMode(!_isSignUp),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: app_colors.P.muted),
                children: [
                  TextSpan(
                      text: _isSignUp
                          ? 'Already in the crew? '
                          : 'Need an account? '),
                  TextSpan(
                    text: _isSignUp ? 'Sign In, Bro' : 'Claim Your Tag',
                    style: const TextStyle(
                      color: app_colors.P.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('By stepping in, you rep the Bro Code.',
              style: AppText.caption),
          if (buildNumber.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('BRO · build $buildNumber',
                style: AppText.caption),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compactHeight = size.height < 700;
    final wide = size.width >= app_colors.adaptiveBreakpoint;
    final reduce = reduceMotionOf(context);
    final showHero = !keyboardOpen && !compactHeight;
    final showFeatureCards = size.height >= 760;

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: _buildForm(context),
    );

    Widget content;
    if (wide && showHero) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 11,
            child: WelcomeHero(
              isSignUp: _isSignUp,
              animate: !reduce,
              showFeatureCards: showFeatureCards,
            ),
          ),
          const SizedBox(width: 48),
          Expanded(flex: 9, child: Center(child: form)),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHero) ...[
            WelcomeHero(
              isSignUp: _isSignUp,
              animate: !reduce,
              showFeatureCards: showFeatureCards,
            ),
            const SizedBox(height: 28),
          ] else if (!keyboardOpen) ...[
            _buildCompactHeader(),
          ],
          form,
        ],
      );
    }

    return Scaffold(
      body: AuthBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                  24, keyboardOpen ? 12 : 20, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide && showHero ? 940 : 460),
                child: content,
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
    // Animation is started/stopped in didChangeDependencies where MediaQuery
    // (OS reduce-motion) is available — keeping this controller quiet in
    // initState makes widget tests deterministic too.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final allow = widget.animate && !reduceMotionOf(context);
    if (allow) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      if (_motion.isAnimating) _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant WelcomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _syncAnimation();
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
                    // ── Decorative depth layers (hidden from screen readers) ──
                    ExcludeSemantics(
                      child: Positioned(
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
                                const Color(0xFF292A35)
                                    .withValues(alpha: 0.16),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.5, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Positioned(
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
                                color: app_colors.P.primary
                                    .withValues(alpha: 0.17),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: app_colors.P.primary
                                      .withValues(alpha: 0.07),
                                  blurRadius: 28,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Headline (kept readable by screen readers)
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
                                color: app_colors.P.surfaceHigh
                                    .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: app_colors.P.border
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle,
                                      size: 7, color: app_colors.P.primary),
                                  SizedBox(width: 7),
                                  const Text(
                                    'BRO  ·  YOUR PEOPLE, CLOSER',
                                    style: AppText.eyebrow,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            heading,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: AppText.heroTitle
                                .copyWith(fontSize: compact ? 25 : 28),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.isSignUp
                                ? 'Make room for the conversations that matter.'
                                : 'All your conversations, right here.',
                            textAlign: TextAlign.center,
                            style: AppText.subtitle,
                          ),
                        ],
                      ),
                    ),
                    // A few glossy 3D collectibles orbit the character.
                    ExcludeSemantics(
                      child: Positioned(
                        left: (compact ? 7.0 : 18.0) + math.sin(phase + 0.4) * 5,
                        bottom: 88 + math.sin(phase + 0.9) * 8,
                        child: _OrbitBall(phase: phase),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Positioned(
                        left: (compact ? 2.0 : 12.0) + math.sin(phase + 2.4) * 5,
                        bottom: 18 + math.sin(phase + 2.1) * 6,
                        child: _OrbitGamepad(phase: phase),
                      ),
                    ),
                    ExcludeSemantics(
                      child: Positioned(
                        right: (compact ? 0.0 : 7.0) + math.sin(phase + 1.1) * 7,
                        bottom: 67 + math.sin(phase + 1.6) * 7,
                        child: _OrbitSupercar(phase: phase),
                      ),
                    ),
                    // A moving contact shadow gives her path a grounded depth cue.
                    ExcludeSemantics(
                      child: Positioned(
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
                    ),
                    // The character travels around the stage rather than staying
                    // pinned in place. Perspective, scale and lean sell the orbit.
                    ExcludeSemantics(
                      child: Positioned(
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
                      ExcludeSemantics(
                        child: Positioned(
                          left: compact ? 1 : 8,
                          top: 181 + math.sin(phase + 1) * 7,
                          child: const _WelcomeFloatCard(
                            icon: Icons.lock_rounded,
                            title: 'Private by design',
                            detail: 'Just your circle',
                            accent: app_colors.P.primary,
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: Positioned(
                          right: compact ? 0 : 8,
                          top: 132 + math.sin(phase + 2.2) * 8,
                          child: const _WelcomeFloatCard(
                            icon: Icons.bolt_rounded,
                            title: 'Always in sync',
                            detail: 'Pick up anywhere',
                            accent: Color(0xFF8DB7FF),
                          ),
                        ),
                      ),
                    ],
                    ExcludeSemantics(
                      child: Positioned(
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
                                color: app_colors.P.primary
                                    .withValues(alpha: 0.35),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.forum_rounded,
                              size: 17, color: app_colors.P.darkOnAccent),
                        ),
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
      child: Image.asset(
        'assets/images/welcome_3d_ball.webp',
        width: 54,
        height: 54,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
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
      child: Image.asset(
        'assets/images/welcome_3d_gamepad.png',
        width: 84,
        height: 58,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );
  }
}

class _OrbitSupercar extends StatelessWidget {
  const _OrbitSupercar({required this.phase});
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Transform(
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
