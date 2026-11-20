/// Pure, synchronous validators shared by the auth surfaces.
///
/// Kept free of Flutter imports so they can be unit tested cheaply and reused
/// by both the login screen and any future auth entry point.
library;

/// Returns null when [input] looks like a usable email address, otherwise a
/// human-readable error.
String? validateEmail(String input) {
  final email = input.trim();
  if (email.isEmpty || RegExp(r'\s').hasMatch(email)) {
    return "That email doesn't look quite right.";
  }
  final parts = email.split('@');
  if (parts.length != 2 ||
      parts.first.isEmpty ||
      !parts.last.contains('.') ||
      parts.last.startsWith('.') ||
      parts.last.endsWith('.')) {
    return "That email doesn't look quite right.";
  }
  return null;
}

/// BRO passwords must be at least 6 characters (matches the Supabase policy).
String? validatePassword(String input) {
  if (input.length < 6) {
    return 'Use at least 6 characters for your password.';
  }
  return null;
}

/// Usernames: at least 3 chars; letters, numbers, dots, dashes, underscores.
String? validateUsername(String input) {
  final username = input.trim();
  if (username.length < 3 ||
      !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
    return 'Usernames need at least 3 letters, numbers, dots, dashes, or underscores.';
  }
  return null;
}
