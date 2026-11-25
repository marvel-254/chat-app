import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/supabase.dart';
import '../../../theme/app_colors.dart' as app_colors;
import '../../../ui/errors.dart';

/// Prompts the user to re-authenticate before performing a sensitive account
/// action (changing password, disabling 2FA, or deleting their account).
///
/// Uses a 6-digit TOTP code when a verified TOTP factor is enrolled, or
/// falls back to verifying the user's current password.
Future<bool> showReauthDialog(
  BuildContext context, {
  String title = 'Verify it’s you',
  String subtitle = 'Confirm your identity before making this security change.',
}) async {
  Factor? totpFactor;
  try {
    final factors = await Supa.listMfaFactors();
    totpFactor = factors.totp.firstOrNull;
  } catch (_) {
    totpFactor = null;
  }

  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ReauthDialog(
      title: title,
      subtitle: subtitle,
      totpFactor: totpFactor,
    ),
  );
  return result == true;
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({
    required this.title,
    required this.subtitle,
    required this.totpFactor,
  });

  final String title;
  final String subtitle;
  final Factor? totpFactor;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _input = TextEditingController();
  bool _verifying = false;
  late bool _useTotp = widget.totpFactor != null;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _input.text.trim();
    if (_useTotp) {
      if (!RegExp(r'^\d{6}$').hasMatch(value)) {
        setState(() => _error = 'Enter the 6-digit code from your app.');
        return;
      }
    } else if (_input.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      if (_useTotp && widget.totpFactor != null) {
        await Supa.verifyTotp(factorId: widget.totpFactor!.id, code: value);
      } else {
        await Supa.reauthenticateWithPassword(_input.text);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback: _useTotp
                  ? "That 6-digit code didn't match."
                  : "That password didn't match.",
            ));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.subtitle,
            style: const TextStyle(color: app_colors.P.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          if (_error != null) SoftErrorBanner(message: _error!),
          TextField(
            controller: _input,
            autofocus: true,
            obscureText: !_useTotp,
            keyboardType:
                _useTotp ? TextInputType.number : TextInputType.visiblePassword,
            decoration: InputDecoration(
              labelText: _useTotp ? '6-digit authenticator code' : 'Current password',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.totpFactor != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _verifying
                  ? null
                  : () {
                      _input.clear();
                      setState(() {
                        _useTotp = !_useTotp;
                        _error = null;
                      });
                    },
              child: Text(
                _useTotp ? 'Use current password instead' : 'Use 2FA code instead',
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _verifying ? null : _submit,
          child: Text(_verifying ? 'Verifying…' : 'Continue'),
        ),
      ],
    );
  }
}
