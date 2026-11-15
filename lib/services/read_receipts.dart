import 'package:supabase_flutter/supabase_flutter.dart';

/// Read receipt preference operations.
///
/// Reads and writes the per-profile read_receipts_enabled flag.
class ReadReceipts {
  ReadReceipts._();

  static SupabaseClient get _client => Supabase.instance.client;
  static User? get _currentUser => _client.auth.currentUser;

  /// Check whether read receipts are enabled for the current user.
  /// Defaults to [true] if the profile cannot be loaded.
  static Future<bool> isEnabled() async {
    final me = _currentUser;
    if (me == null) return true;
    final res = await _client
        .from('profiles')
        .select('read_receipts_enabled')
        .eq('id', me.id)
        .maybeSingle();
    if (res == null) return true;
    return res['read_receipts_enabled'] as bool? ?? true;
  }

  /// Enable or disable read receipts for the current user.
  static Future<void> setEnabled(bool enabled) async {
    final me = _currentUser;
    if (me == null) return;
    await _client
        .from('profiles')
        .update({'read_receipts_enabled': enabled})
        .eq('id', me.id);
  }
}
