import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps thrown errors to short, calm copy. Never returns stack traces,
/// PostgREST guts, or `Exception: ...` prefixes.
String friendlyErrorMessage(
  Object? error, {
  String fallback = "Something didn't work. Please try again.",
}) {
  if (error == null) return fallback;

  if (error is String) {
    final trimmed = error.trim();
    if (trimmed.isEmpty) return fallback;
    return _softenKnown(trimmed, fallback);
  }

  if (error is AuthRetryableFetchException) {
    return "Can't reach BRO right now. Check your connection and try again.";
  }

  if (error is AuthException) {
    return _authMessage(error, fallback);
  }

  if (error is PostgrestException) {
    return _postgrestMessage(error, fallback);
  }

  if (error is ArgumentError) {
    final message = error.message?.toString().trim();
    if (message != null && message.isNotEmpty) {
      return _softenKnown(message, fallback);
    }
    return fallback;
  }

  if (error is StateError) {
    return _softenKnown(error.message, fallback);
  }

  if (error is FormatException || error is http.ClientException) {
    return "We couldn't reach the server. Check your connection and try again.";
  }

  return _softenKnown(error.toString(), fallback);
}

String _authMessage(AuthException error, String fallback) {
  final code = error.code ?? '';
  final message = error.message.toLowerCase();

  switch (code) {
    case 'invalid_credentials':
    case 'invalid_grant':
      return "That email or password doesn't match. Double-check and try again.";
    case 'email_not_confirmed':
      return 'Please confirm your email, then come back to sign in.';
    case 'user_already_exists':
      return 'That email already has an account. Try signing in instead.';
    case 'signup_disabled':
      return "New accounts aren't being created right now.";
    case 'weak_password':
      return 'Please choose a longer password — at least 6 characters.';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return "We've sent a few emails already. Please wait a minute and try again.";
    case 'email_address_invalid':
      return "That email doesn't look quite right.";
    case 'same_password':
      return 'Please pick a password you have not used here before.';
  }

  if (message.contains('invalid login') ||
      message.contains('invalid credentials')) {
    return "That email or password doesn't match. Double-check and try again.";
  }
  if (message.contains('already registered') ||
      message.contains('already been registered')) {
    return 'That email already has an account. Try signing in instead.';
  }
  if (message.contains('rate limit') || message.contains('too many')) {
    return 'Please wait a moment, then try again.';
  }
  if (message.contains('network') || message.contains('fetch')) {
    return "Can't reach BRO right now. Check your connection and try again.";
  }
  if (message.contains('security purposes') ||
      message.contains('only request this')) {
    return 'Please wait a minute before requesting another email.';
  }
  return fallback;
}

String _postgrestMessage(PostgrestException error, String fallback) {
  final message = '${error.message} ${error.details ?? ''} ${error.code ?? ''}'
      .toLowerCase();
  return _softenKnown(message, fallback);
}

String _softenKnown(String raw, String fallback) {
  final message = raw.toLowerCase();

  if (message.contains('invalid login') ||
      message.contains('invalid credentials')) {
    return "That email or password doesn't match. Double-check and try again.";
  }
  if (message.contains('cannot message') ||
      message.contains('cannot start a conversation with this user')) {
    return "You can't message this person right now.";
  }
  if (message.contains('cannot start a conversation with yourself')) {
    return "That's you — pick someone else to chat with.";
  }
  if (message.contains('rate limit')) {
    return "You're sending a bit fast. Take a breath and try again in a moment.";
  }
  if (message.contains('message too long')) {
    return "That's a bit long — try shortening it to 4000 characters.";
  }
  if (message.contains('message cannot be empty')) {
    return 'Write a little something before sending.';
  }
  if (message.contains('suspicious')) {
    return "That message looks like it might be unsafe, so we held it back.";
  }
  if (message.contains('not a participant') ||
      message.contains('row-level security') ||
      message.contains('42501') ||
      message.contains('permission denied') ||
      message.contains('rls')) {
    return "You don't have access to that.";
  }
  if (message.contains('23505') ||
      message.contains('duplicate key') ||
      message.contains('profiles_username')) {
    return 'That username is taken. Try another?';
  }
  if (message.contains('edit window has expired')) {
    return 'Edits are only available for a few minutes after sending.';
  }
  if (message.contains('at most 5 pinned')) {
    return 'You can pin up to 5 messages in a chat. Unpin one first.';
  }
  if (message.contains('only the message author may pin')) {
    return 'Only the person who sent it can pin that message.';
  }
  if (message.contains('unauthenticated') ||
      message.contains('jwt') ||
      message.contains('not authenticated')) {
    return 'Please sign in again to continue.';
  }
  if (message.contains('last_message_at') ||
      message.contains('schema cache')) {
    return "That message didn't land cleanly. Try sending it once more.";
  }
  if (message.contains('socket') ||
      message.contains('failed host lookup') ||
      message.contains('connection refused') ||
      message.contains('network')) {
    return "Can't reach BRO right now. Check your connection and try again.";
  }
  if (message.contains('cloud storage') ||
      message.contains('storage request failed')) {
    return "We couldn't upload that file. Check your connection and try again.";
  }
  if (message.startsWith('exception:') ||
      message.startsWith('stateerror:') ||
      message.startsWith('error:') ||
      message.contains('postgrest') ||
      message.contains('postgres') ||
      message.contains('stack')) {
    return fallback;
  }

  final cleaned = raw.replaceFirst(RegExp(r'^(Exception|StateError|Error):\s*'), '');
  if (cleaned.length > 180) return fallback;
  if (RegExp(r'[{}\[\]]').hasMatch(cleaned)) return fallback;
  return cleaned.trim().isEmpty ? fallback : cleaned.trim();
}

/// Calm inline banner for form-level errors (login, settings, confirm).
class SoftErrorBanner extends StatelessWidget {
  const SoftErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onSurface,
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
