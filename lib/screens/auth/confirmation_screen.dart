import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../ui/errors.dart';
import '../../ui/states.dart' show BroSpinner;
import 'widgets/bro_wordmark.dart';

class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key, required this.email});
  final String email;

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _resending = false;
  String? _error;
  bool _sent = false;

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _sent = false;
    });
    try {
      await Supa.resendConfirmation(widget.email);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = friendlyErrorMessage(
            e,
            fallback:
                "We couldn't resend that email just now. Please try again in a moment.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: app_colors.P.bg,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BroWordmark(),
                  const SizedBox(height: 28),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: app_colors.P.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: app_colors.P.primary.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: app_colors.P.primary.withValues(alpha: 0.12),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.mark_email_unread_outlined,
                        color: app_colors.P.primary,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Check your email',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: app_colors.P.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a confirmation link to\n${widget.email}. Tap it to activate your account, then sign in.',
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: app_colors.P.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: SoftErrorBanner(message: _error!),
                    ),
                  if (_sent)
                    const _InfoNote(
                      message: 'Confirmation email sent again. Check your inbox.',
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _resending ? null : _resend,
                      icon: _resending
                          ? const BroSpinner(
                              size: 18, color: app_colors.P.text)
                          : const Icon(Icons.mark_email_read_outlined),
                      label: Text(
                        _resending ? 'Sending…' : 'Resend confirmation',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: app_colors.P.text,
                        side: BorderSide(
                          color: app_colors.P.primary.withValues(alpha: 0.4),
                        ),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text(
                      'Back to Sign In',
                      style: TextStyle(
                        color: app_colors.P.primary,
                        fontWeight: FontWeight.w600,
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

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: app_colors.P.success.withValues(alpha: 0.10),
        border: Border.all(color: app_colors.P.success.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: app_colors.P.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: app_colors.P.text,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
