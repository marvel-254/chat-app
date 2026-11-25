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

/// Password strength level for live feedback on sign-up and password changes.
enum PasswordStrength { weak, fair, strong }

/// Returns null when [input] meets BRO's password policy:
/// at least 8 characters and at least two character classes
/// (letters, numbers, or symbols).
String? validatePassword(String input) {
  if (input.length < 8) {
    return 'Use at least 8 characters for your password.';
  }
  final hasLower = RegExp(r'[a-z]').hasMatch(input);
  final hasUpper = RegExp(r'[A-Z]').hasMatch(input);
  final hasDigit = RegExp(r'[0-9]').hasMatch(input);
  final hasSymbol = RegExp(r'[^a-zA-Z0-9\s]').hasMatch(input);
  final classes = [hasLower || hasUpper, hasDigit, hasSymbol].where((c) => c).length;
  if (classes < 2) {
    return 'Mix in at least two of letters, numbers, or symbols.';
  }
  return null;
}

/// Sign-in password validation: avoids locking out legacy accounts while
/// rejecting obviously empty/too-short inputs.
String? validateSignInPassword(String input) {
  if (input.length < 6) {
    return 'Use at least 6 characters for your password.';
  }
  return null;
}

/// Evaluates [password] into a 3-tier [PasswordStrength] for UI feedback.
PasswordStrength evaluatePasswordStrength(String password) {
  if (password.length < 8) return PasswordStrength.weak;
  final hasLower = RegExp(r'[a-z]').hasMatch(password);
  final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
  final hasDigit = RegExp(r'[0-9]').hasMatch(password);
  final hasSymbol = RegExp(r'[^a-zA-Z0-9\s]').hasMatch(password);
  final classes = [hasLower, hasUpper, hasDigit, hasSymbol].where((c) => c).length;
  if (password.length >= 12 && classes >= 3) {
    return PasswordStrength.strong;
  }
  if (classes >= 2 && (password.length >= 10 || classes >= 3)) {
    return PasswordStrength.strong;
  }
  if (classes >= 2) {
    return PasswordStrength.fair;
  }
  return PasswordStrength.weak;
}

/// Progressive client-side cooldown after repeated failed sign-in attempts.
/// Returns `Duration.zero` for fewer than 3 consecutive failures.
Duration loginCooldownForFailures(int consecutiveFailures) {
  if (consecutiveFailures < 3) return Duration.zero;
  if (consecutiveFailures == 3) return const Duration(seconds: 5);
  if (consecutiveFailures == 4) return const Duration(seconds: 15);
  return const Duration(seconds: 30);
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
