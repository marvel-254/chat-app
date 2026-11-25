import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/supabase.dart';
import '../../../theme/app_colors.dart' as app_colors;
import '../../../ui/errors.dart';

/// Walks the user through enrolling a TOTP authenticator app and verifying
/// the first 6-digit code. Returns `true` when enrollment is verified.
Future<bool> showTotpEnrollmentDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TotpEnrollmentDialog(),
  );
  return result == true;
}

class _TotpEnrollmentDialog extends StatefulWidget {
  const _TotpEnrollmentDialog();

  @override
  State<_TotpEnrollmentDialog> createState() => _TotpEnrollmentDialogState();
}

class _TotpEnrollmentDialogState extends State<_TotpEnrollmentDialog> {
  final _code = TextEditingController();
  AuthMFAEnrollResponse? _enrollment;
  bool _loading = true;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    try {
      final res = await Supa.enrollTotp();
      if (!mounted) return;
      setState(() {
        _enrollment = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(
          e,
          fallback: "We couldn't start 2FA setup right now.",
        );
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    final factorId = _enrollment?.id;
    if (factorId == null) return;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from your app.');
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await Supa.verifyTotp(factorId: factorId, code: code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyErrorMessage(
              e,
              fallback:
                  "That 6-digit code didn't match. Check your authenticator app and try again.",
            ));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _cancel() async {
    final factorId = _enrollment?.id;
    if (factorId != null) {
      try {
        await Supa.unenrollMfaFactor(factorId);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final totp = _enrollment?.totp;
    return AlertDialog(
      title: const Text('Set up Two-Factor Auth'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) SoftErrorBanner(message: _error!),
                    if (totp != null) ...[
                      const Text(
                        'Scan this QR code or copy the setup key into your authenticator app (Google Authenticator, 1Password, Authy, etc.), then enter the 6-digit code below.',
                        style: TextStyle(color: app_colors.P.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      if (kIsWeb)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.network(
                              totp.qrCode,
                              width: 180,
                              height: 180,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 180,
                                height: 180,
                                child: Center(
                                  child: Text(
                                    'Use the setup key below',
                                    style: TextStyle(color: Colors.black54),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: app_colors.P.surfaceLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: app_colors.P.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                totp.secret,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy setup key',
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: totp.secret));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Setup key copied.')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open in Authenticator app'),
                          onPressed: () {
                            final uri = Uri.tryParse(totp.uri);
                            if (uri != null) {
                              launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '6-digit verification code',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _verify(),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : _cancel,
          child: const Text('Cancel'),
        ),
        if (totp != null)
          FilledButton(
            onPressed: _verifying ? null : _verify,
            child: Text(_verifying ? 'Verifying…' : 'Enable 2FA'),
          ),
      ],
    );
  }
}
