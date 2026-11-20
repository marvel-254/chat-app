/// Compatibility policy for the old server-readable transport. There is no
/// secure-send path yet. Consent is account-scoped and never persisted.
class LegacyMessaging {
  static String? _owner;
  static bool allowed(String? user) => user != null && _owner == user;
  static void allow(String user) => _owner = user;
  static void reset() => _owner = null;
  static void requireAllowed(String? user) {
    if (!allowed(user)) {
      throw StateError('Enable legacy messaging in the chat first.');
    }
  }
}
