import 'legacy_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Message reaction operations (add, remove, query, watch).
class Reactions {
  Reactions._();

  static SupabaseClient get _client => Supabase.instance.client;

  static User? get _currentUser => _client.auth.currentUser;

  /// Add or upsert a reaction. Idempotent via ON CONFLICT.
  static Future<void> add(String messageId, String emoji) async {
    final me = _currentUser;
    if (me == null) return;
    LegacyMessaging.requireAllowed(me.id);
    await _client.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': me.id,
      'emoji': emoji,
    }, onConflict: 'message_id,user_id,emoji', ignoreDuplicates: true);
  }

  /// Remove the current user's reaction [emoji] from [messageId].
  static Future<void> remove(String messageId, String emoji) async {
    final me = _currentUser;
    if (me == null) return;
    await _client
        .from('message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', me.id)
        .eq('emoji', emoji);
  }

  /// Fetch all reactions for a message, ordered by creation time.
  static Future<List<Map<String, dynamic>>> getAll(String messageId) async {
    final res = await _client
        .from('message_reactions')
        .select('emoji,user_id,created_at')
        .eq('message_id', messageId)
        .order('created_at', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Realtime stream of reactions for a message.
  static Stream<List<Map<String, dynamic>>> watch(String messageId) {
    return _client
        .from('message_reactions')
        .stream(primaryKey: ['id'])
        .eq('message_id', messageId)
        .map((rows) => rows.toList());
  }
}
