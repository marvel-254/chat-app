import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/connection_monitor.dart';
import '../../services/hibp_password_check.dart';
import '../../ui/errors.dart';
import '../../ui/motion.dart';
import '../../ui/auth_backdrop.dart';
import '../../theme/app_text.dart';
import '../../app_constants.dart';
import 'auth_validation.dart';
import 'widgets/auth_controls.dart';
import 'widgets/auth_prop_backdrop.dart';
import 'widgets/bro_wordmark.dart';
import 'widgets/password_strength_meter.dart';
import 'widgets/turnstile_widget.dart';
import 'widgets/welcome_hero.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onSignIn,
    this.onLeakedCheck,
  });

  /// Optional test hook overriding `Supa.signIn`.
  final Future<void> Function(String email, String password)? onSignIn;

  /// Optional test hook overriding `HibpPasswordCheck.isLeaked`.
  final Future<bool> Function(String password)? onLeakedCheck;

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
  String? _captchaToken;
  int _failedSignInAttempts = 0;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      if (_isSignUp && mounted) setState(() {});
    });
  }

  void _startCooldown(Duration duration) {
    _cooldownTimer?.cancel();
    if (duration <= Duration.zero) return;
    setState(() => _cooldownSeconds = duration.inSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

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
      errors['password'] = validatePassword(password);
    } else {
      errors['password'] = validateSignInPassword(password);
    }
    errors['email'] = validateEmail(email);
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
    if (_cooldownSeconds > 0 && !_isSignUp) return;
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
      if (!ConnectionMonitor.isOnline.value && widget.onSignIn == null) {
        if (mounted) {
          setState(() =>
              _error = "You're offline. Check your connection and try again.");
        }
        return;
      }
      final email = _email.text.trim();
      final password = _password.text;
      if (_isSignUp) {
        final leaked = await (widget.onLeakedCheck ??
            HibpPasswordCheck.isLeaked)(password);
        if (leaked) {
          if (mounted) {
            setState(() {
              _fieldErrors['password'] =
                  'This password has appeared in a known data breach. Please choose a different one.';
            });
          }
          return;
        }
        final res = await Supa.signUp(
          email,
          password,
          _username.text.trim(),
          captchaToken: _captchaToken,
        );
        // Supabase may require email confirmation before sign-in is allowed.
        // If no session was created, the user must confirm their email first.
        if (res.session == null) {
          if (mounted) {
            context.go('/confirm', extra: email);
          }
          return;
        }
      } else {
        if (widget.onSignIn != null) {
          await widget.onSignIn!(email, password);
          _failedSignInAttempts = 0;
          return;
        }
        await Supa.signIn(email, password, captchaToken: _captchaToken);
        _failedSignInAttempts = 0;
        if (Supa.needsMfaChallenge()) {
          if (mounted) context.go('/mfa-challenge');
          return;
        }
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
      if (!_isSignUp) {
        _failedSignInAttempts += 1;
        final cooldown = loginCooldownForFailures(_failedSignInAttempts);
        if (cooldown > Duration.zero) {
          _startCooldown(cooldown);
        }
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
      await Supa.resetPasswordForEmail(email, captchaToken: _captchaToken);
      if (mounted) {
        setState(() => _notice =
            'If an account exists for $email, a reset link is on the way. Check your inbox.');
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

  Future<void> _signInWithOAuth(OAuthProvider provider) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await Supa.signInWithOAuth(provider);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback: "We couldn't start social sign-in right now.",
            ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
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

          ValueListenableBuilder<bool>(
            valueListenable: ConnectionMonitor.isOnline,
            builder: (context, online, _) {
              if (online) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: AuthNoticeBanner(
                    message: "You're offline. Signing in needs a connection."),
              );
            },
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: SoftErrorBanner(message: _error!),
            ),
          if (_notice != null)
            Semantics(
                liveRegion: true, child: AuthNoticeBanner(message: _notice!)),

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
            autofillHints: isSignIn
                ? const [AutofillHints.email]
                : const [AutofillHints.newUsername, AutofillHints.email],
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
            helperText: _isSignUp
                ? 'At least 8 characters with letters and numbers or symbols.'
                : null,
            onFocus: () {
              _clearFieldError('password');
              setState(() => _guideTarget = 'password');
            },
          ),
          if (_isSignUp) PasswordStrengthMeter(password: _password.text),
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

          TurnstileWidget(
            onToken: (token) => _captchaToken = token,
          ),
          if (_cooldownSeconds > 0 && isSignIn)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Too many attempts. Try again in ${_cooldownSeconds}s.',
                style: const TextStyle(
                  color: Color(0xFFFF8D8D),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // CTA
          AuthPrimaryButton(
            key: const Key('auth-cta'),
            label: _isSignUp
                ? 'Create Account'
                : (_cooldownSeconds > 0
                    ? 'Wait ${_cooldownSeconds}s'
                    : 'Sign In'),
            loading: _loading,
            onPressed: (_cooldownSeconds > 0 && isSignIn) ? null : _submit,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _signInWithOAuth(OAuthProvider.google),
                  icon: const Icon(Icons.g_mobiledata, size: 22),
                  label: const Text('Google'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: app_colors.P.text,
                    side: BorderSide(color: app_colors.P.border),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _signInWithOAuth(OAuthProvider.github),
                  icon: const Icon(Icons.code, size: 18),
                  label: const Text('GitHub'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: app_colors.P.text,
                    side: BorderSide(color: app_colors.P.border),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loading ? null : () => _switchMode(!_isSignUp),
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
            Text('BRO · build $buildNumber', style: AppText.caption),
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
    final wide = size.width >= app_colors.desktopBreakpoint;
    final reduce = reduceMotionOf(context);
    final showHero = !keyboardOpen && !compactHeight;

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: _buildForm(context),
    );

    Widget content;
    if (wide && showHero) {
      // The prop is the page background (see AuthPropBackdrop), so the copy and
      // the form stack in one column on the left and she keeps the right.
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WelcomeHero(
                  isSignUp: _isSignUp,
                  animate: !reduce,
                  showProp: false,
                ),
                const SizedBox(height: 28),
                form,
              ],
            ),
          ),
          const Spacer(flex: 9),
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
              showProp: false,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            const AuthPropBackdrop(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding:
                      EdgeInsets.fromLTRB(24, keyboardOpen ? 12 : 20, 24, 24),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: wide && showHero ? 940 : 460),
                    child: content,
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
