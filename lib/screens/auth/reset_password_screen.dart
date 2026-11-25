import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/hibp_password_check.dart';
import '../../services/supabase.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../theme/app_text.dart';
import '../../ui/auth_backdrop.dart';
import '../../ui/errors.dart';
import 'auth_validation.dart';
import 'widgets/auth_controls.dart';
import 'widgets/bro_wordmark.dart';
import 'widgets/password_strength_meter.dart';

/// Dedicated screen reached via `AuthChangeEvent.passwordRecovery` (`/reset-password`).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    this.onUpdatePassword,
    this.onLeakedCheck,
    this.onComplete,
  });

  /// Optional test hook to override `Supa.client.auth.updateUser`.
  final Future<void> Function(String newPassword)? onUpdatePassword;

  /// Optional test hook to override `HibpPasswordCheck.isLeaked`.
  final Future<bool> Function(String password)? onLeakedCheck;

  /// Optional test hook called after password reset succeeds.
  final VoidCallback? onComplete;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _passwordError;
  String? _confirmError;

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pwd = _password.text;
    final confirm = _confirm.text;
    final pwdErr = validatePassword(pwd);
    final confirmErr =
        pwd != confirm ? 'Those passwords do not match.' : null;

    setState(() {
      _passwordError = pwdErr;
      _confirmError = confirmErr;
      _error = null;
    });
    if (pwdErr != null || confirmErr != null) return;

    setState(() => _loading = true);
    try {
      final leaked = await (widget.onLeakedCheck ?? HibpPasswordCheck.isLeaked)(
        pwd,
      );
      if (leaked) {
        if (mounted) {
          setState(() {
            _passwordError =
                'This password has appeared in a known data breach. Please choose a different one.';
          });
        }
        return;
      }

      if (widget.onUpdatePassword != null) {
        await widget.onUpdatePassword!(pwd);
      } else {
        await Supa.client.auth.updateUser(UserAttributes(password: pwd));
        Supa.passwordRecoveryPending.value = false;
      }

      if (!mounted) return;
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password updated. Welcome back!')),
        );
        context.go('/conversations');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback: "We couldn't update your password. Please try again.",
            ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BroWordmark(fontSize: 22),
                    const SizedBox(height: 18),
                    const Text(
                      'Set a new password',
                      textAlign: TextAlign.center,
                      style: AppText.heroTitleCompact,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a strong password you have not used elsewhere.',
                      textAlign: TextAlign.center,
                      style: AppText.subtitle,
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) SoftErrorBanner(message: _error!),
                    AuthTextField(
                      controller: _password,
                      label: 'New password',
                      prefix: Icons.lock_outline,
                      placeholder: '••••••••',
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      errorText: _passwordError,
                      helperText:
                          'At least 8 characters with letters and numbers or symbols.',
                      onFocus: () => setState(() => _passwordError = null),
                    ),
                    PasswordStrengthMeter(password: _password.text),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _confirm,
                      label: 'Confirm password',
                      prefix: Icons.lock_outline,
                      placeholder: '••••••••',
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      autofillHints: const [AutofillHints.newPassword],
                      errorText: _confirmError,
                      onFocus: () => setState(() => _confirmError = null),
                    ),
                    const SizedBox(height: 24),
                    AuthPrimaryButton(
                      key: const Key('reset-password-cta'),
                      label: 'Update Password',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              await Supa.signOut();
                              if (context.mounted) context.go('/login');
                            },
                      child: const Text(
                        'Back to Sign In',
                        style: TextStyle(color: app_colors.P.muted),
                      ),
                    ),
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
