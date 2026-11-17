import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../ui/errors.dart';
import '../../ui/states.dart';

class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key, required this.email});
  final String email;

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _resending = false;
  String? _error;

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await Supa.resendConfirmation(widget.email);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback:
                  "We couldn't resend that email just now. Please try again in a moment.",
            ));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: app_colors.P.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: app_colors.P.border),
                  ),
                  child: const Center(
                    child: Icon(Icons.mark_email_unread_outlined,
                        color: app_colors.P.primary, size: 40),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Check Your Email',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: app_colors.P.text)),
                const SizedBox(height: 8),
                Text(
                  'We sent a confirmation link to\n${widget.email}. Click it to activate your account, then sign in.',
                  style: const TextStyle(
                      fontSize: 15, color: app_colors.P.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_error != null) SoftErrorBanner(message: _error!),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _resending ? null : _resend,
                    icon: _resending
                        ? const BroSpinner(size: 18, color: app_colors.P.text)
                        : const Icon(Icons.mark_email_read_outlined,
                            color: app_colors.P.text),
                    label: Text(_resending ? 'Sending…' : 'Resend Confirmation',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: app_colors.P.text,
                      side: const BorderSide(color: app_colors.P.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Sign In',
                      style: TextStyle(color: app_colors.P.primary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

