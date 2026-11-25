import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/supabase.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../theme/app_text.dart';
import '../../ui/auth_backdrop.dart';
import '../../ui/errors.dart';
import 'widgets/auth_controls.dart';
import 'widgets/bro_wordmark.dart';

/// Second-factor TOTP verification gate shown when a signed-in session is
/// at AAL1 and the account has a verified TOTP factor (`nextLevel == aal2`).
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({
    super.key,
    this.onVerifyCode,
    this.onVerified,
  });

  /// Optional test hook overriding TOTP challenge+verify.
  final Future<void> Function(String code)? onVerifyCode;

  /// Optional test hook called after successful verification.
  final VoidCallback? onVerified;

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _codeError;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _codeError = 'Enter the 6-digit code from your app.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _codeError = null;
    });

    try {
      if (widget.onVerifyCode != null) {
        await widget.onVerifyCode!(code);
      } else {
        final factors = await Supa.listMfaFactors();
        final totp = factors.totp.firstOrNull;
        if (totp == null) {
          throw StateError('No active two-factor method was found.');
        }
        await Supa.verifyTotp(factorId: totp.id, code: code);
      }
      if (!mounted) return;
      if (widget.onVerified != null) {
        widget.onVerified!();
      } else {
        context.go('/conversations');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback:
                  "That 6-digit code didn't match. Check your authenticator app and try again.",
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
                      'Two-factor verification',
                      textAlign: TextAlign.center,
                      style: AppText.heroTitleCompact,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enter the 6-digit code from your authenticator app to continue.',
                      textAlign: TextAlign.center,
                      style: AppText.subtitle,
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) SoftErrorBanner(message: _error!),
                    AuthTextField(
                      controller: _code,
                      label: '6-digit code',
                      prefix: Icons.shield_outlined,
                      placeholder: '123456',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _verify(),
                      errorText: _codeError,
                      onFocus: () => setState(() => _codeError = null),
                    ),
                    const SizedBox(height: 24),
                    AuthPrimaryButton(
                      key: const Key('mfa-verify-cta'),
                      label: 'Verify',
                      loading: _loading,
                      onPressed: _verify,
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
                        'Sign out',
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
