import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'e2ee.dart';

class Reactions {
  static SupabaseClient get _client => Supabase.instance.client;
  static Future<String> _conversation(String id) async => (await _client
      .from('messages')
      .select('conversation_id')
      .eq('id', id)
      .single())['conversation_id'] as String;
  static Future<Map<String, dynamic>> decode(
      Map<String, dynamic> row, String conversation) async {
    final sealed = row['sealed_content'];
    if (sealed == null) return row;
    try {
      return {
        ...row,
        'emoji': await SecureChat.open(sealed as String, row['id'] as String,
            conversation, row['user_id'] as String, row['message_id'] as String,
            purpose: 'reaction')
      };
    } catch (_) {
      return {...row, 'emoji': '🔒'};
    }
  }

  static Future<void> add(String messageId, String emoji) async {
    final sender = _client.auth.currentUser!.id;
    final id = const Uuid().v4();
    final sealed = await SecureChat.seal(
        id, await _conversation(messageId), emoji,
        reply: messageId, purpose: 'reaction');
    await _client.from('message_reactions').insert({
      'id': id,
      'message_id': messageId,
      'user_id': sender,
      'emoji': id,
      'sealed_content': sealed
    });
  }

  static Future<void> remove(String messageId, String emoji) async {
    final owner = _client.auth.currentUser!.id;
    for (final row in await getAll(messageId)) {
      if (row['emoji'] == emoji && row['user_id'] == owner)
        await _client
            .from('message_reactions')
            .delete()
            .eq('id', row['id'])
            .eq('user_id', owner);
    }
  }

  static Future<List<Map<String, dynamic>>> getAll(String messageId) async {
    final conversation = await _conversation(messageId);
    final rows = await _client
        .from('message_reactions')
        .select()
        .eq('message_id', messageId);
    return Future.wait(rows.map((r) => decode(r, conversation)));
  }

  static Stream<List<Map<String, dynamic>>> watch(String messageId) => _client
      .from('message_reactions')
      .stream(primaryKey: ['id'])
      .eq('message_id', messageId)
      .asyncMap((_) => getAll(messageId));
}
