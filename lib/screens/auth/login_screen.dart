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
                    _WelcomeHero(isSignUp: _isSignUp),
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

/// Full-body welcome artwork alongside the sign-in copy.
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.isSignUp});
  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 312,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;
          final avatarWidth = compact ? 108.0 : 132.0;
          final gap = compact ? 8.0 : 12.0;
          final headingSize = compact ? 22.0 : 25.0;
          final taglineSize = compact ? 12.5 : 14.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: avatarWidth,
                height: 300,
                child: Semantics(
                  image: true,
                  label:
                      'BRO character waving and pointing toward the sign-in fields',
                  child: Image.asset(
                    'assets/images/welcome_avatar_fullbody.png',
                    width: avatarWidth,
                    height: 300,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isSignUp
                          ? 'Your people. Your place.'
                          : 'Good to see you, Bro.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: headingSize,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: app_colors.P.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isSignUp
                          ? 'Make a space for the conversations that matter.'
                          : 'All your convos, right here.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: taglineSize,
                        height: 1.35,
                        color: app_colors.P.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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

