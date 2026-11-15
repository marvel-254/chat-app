import 'package:supabase_flutter/supabase_flutter.dart';

/// Block and report user operations.
///
/// Manages the blocked_users table and user_reports table.
class BlockReport {
  BlockReport._();

  static SupabaseClient get _client => Supabase.instance.client;
  static User? get _currentUser => _client.auth.currentUser;

  /// Block [userId]. Idempotent via ON CONFLICT.
  static Future<void> block(String userId) async {
    final me = _currentUser;
    if (me == null) return;
    await _client.from('blocked_users').upsert({
      'blocker_id': me.id,
      'blocked_id': userId,
    }, onConflict: 'blocker_id,blocked_id', ignoreDuplicates: true);
  }

  /// Unblock [userId].
  static Future<void> unblock(String userId) async {
    final me = _currentUser;
    if (me == null) return;
    await _client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', me.id)
        .eq('blocked_id', userId);
  }

  /// Check whether [userId] is blocked by the current user.
  static Future<bool> isBlocked(String userId) async {
    final me = _currentUser;
    if (me == null) return false;
    final res = await _client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', me.id)
        .eq('blocked_id', userId)
        .maybeSingle();
    return res != null;
  }

  /// Return the list of user IDs blocked by the current user.
  static Future<List<String>> blockedIds() async {
    final me = _currentUser;
    if (me == null) return [];
    final res = await _client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', me.id);
    return (res as List).map((e) => e['blocked_id'] as String).toList();
  }

  /// Report [userId] for the given [reason].
  static Future<void> report({
    required String userId,
    required String reason,
    String? details,
  }) async {
    final me = _currentUser;
    if (me == null) return;
    await _client.from('user_reports').insert({
      'reporter_id': me.id,
      'reported_id': userId,
      'reason': reason,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
