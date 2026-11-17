import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/linked_devices.dart';
import '../../ui/errors.dart';
import '../../ui/states.dart';
import 'login_screen.dart';

/// Callback type for restarting the app (set by main.dart to avoid circular imports).
RestartAppCallback? restartAppCallback;

typedef RestartAppCallback = void Function();

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supa.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BRO',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 22)),
              SizedBox(height: 18),
              BroSpinner(size: 22),
            ],
          )));
        }
        if (snapshot.hasError) {
          return _AuthErrorState(error: friendlyErrorMessage(snapshot.error));
        }
        final session = snapshot.data?.session;
        if (session != null) {
          // Ensure last_seen is recorded on cold start
          unawaited(Supa.recordLastSeen());
          unawaited(LinkedDevices.registerCurrentDeviceSilently());
          // Navigate to conversations; the router will handle the redirect.
          return const _ConversationListPlaceholder();
        }
        return const LoginScreen();
      },
    );
  }
}

/// Placeholder that navigates to conversations when auth succeeds.
class _ConversationListPlaceholder extends StatelessWidget {
  const _ConversationListPlaceholder();
  @override
  Widget build(BuildContext context) {
    context.go('/conversations');
    return const Scaffold();
  }
}

class _AuthErrorState extends StatelessWidget {
  const _AuthErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined,
                  color: app_colors.P.muted, size: 48),
              const SizedBox(height: 16),
              Text("We can't reach BRO right now",
                  style: TextStyle(
                      color: app_colors.P.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(error,
                  style: TextStyle(
                      color: app_colors.P.muted, fontSize: 14, height: 1.4),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  restartAppCallback?.call();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
