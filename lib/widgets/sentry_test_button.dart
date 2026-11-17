import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// A test button that throws an error to verify Sentry error tracking.
/// Place this widget in your app during development to confirm Sentry is working.
class SentryTestButton extends StatelessWidget {
  const SentryTestButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        Sentry.captureMessage('Sentry test error - everything is working!');
        throw ErrorDescription('Sentry test error - this is expected');
      },
      child: const Text('Break the world'),
    );
  }
}
