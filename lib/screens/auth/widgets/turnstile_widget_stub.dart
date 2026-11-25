import 'package:flutter/material.dart';

/// Cloudflare Turnstile site key injected at build time via `--dart-define`.
const String turnstileSiteKey = String.fromEnvironment('TURNSTILE_SITE_KEY');

/// Non-web stub for [TurnstileWidget]. Renders nothing on mobile/desktop.
class TurnstileWidget extends StatelessWidget {
  const TurnstileWidget({
    super.key,
    required this.onToken,
  });

  final ValueChanged<String?> onToken;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
