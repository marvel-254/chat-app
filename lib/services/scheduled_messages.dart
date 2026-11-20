import 'e2ee.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A message that will be delivered at a future time.
class ScheduledMessage {
  final String id;
  final String senderId;
  final String conversationId;
  final String content;
  final String? attachmentUrl;
  final String? attachmentMime;
  final String? replyToId;
  final DateTime scheduledAt;
  final DateTime createdAt;

  ScheduledMessage({
    required this.id,
    required this.senderId,
    required this.conversationId,
    required this.content,
    this.attachmentUrl,
    this.attachmentMime,
    this.replyToId,
    required this.scheduledAt,
    required this.createdAt,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) =>
      ScheduledMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        conversationId: json['conversation_id'] as String,
        content: json['content'] as String,
        attachmentUrl: json['attachment_url'] as String?,
        attachmentMime: json['attachment_mime'] as String?,
        replyToId: json['reply_to_id'] as String?,
        scheduledAt: json['scheduled_at'] is DateTime
            ? json['scheduled_at'] as DateTime
            : DateTime.parse(json['scheduled_at'] as String),
        createdAt: json['created_at'] is DateTime
            ? json['created_at'] as DateTime
            : DateTime.parse(json['created_at'] as String),
      );
}

class ScheduledMessages {
  ScheduledMessages._();

  static SupabaseClient get _client => Supabase.instance.client;

  /// Insert a message that will be delivered at [scheduledAt].
  static Future<ScheduledMessage> schedule({
    required String conversationId,
    required String content,
    required DateTime scheduledAt,
    String? replyToId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final id = const Uuid().v4();
    final sealed =
        await SecureChat.seal(id, conversationId, content, reply: replyToId);
    final res = await _client
        .from('scheduled_messages')
        .insert({
          'id': id,
          'sender_id': user.id,
          'conversation_id': conversationId,
          'content': sealed,
          if (replyToId != null) 'reply_to_id': replyToId,
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
        })
        .select()
        .single();

    return ScheduledMessage.fromJson(res);
  }

  /// Fetch all scheduled messages for the current user.
  static Future<List<ScheduledMessage>> list() async {
    final res = await _client
        .from('scheduled_messages')
        .select()
        .order('scheduled_at', ascending: true);
    return (res as List).map((e) => ScheduledMessage.fromJson(e)).toList();
  }

  /// Cancel (delete) a scheduled message.
  static Future<void> cancel(String id) async {
    await _client.from('scheduled_messages').delete().eq('id', id);
  }

  /// Fetch and deliver any scheduled messages whose time has arrived.
  /// Returns the list of messages that are due (caller should send them).
  static Future<List<ScheduledMessage>> fetchDue() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final res = await _client
        .from('scheduled_messages')
        .select()
        .lte('scheduled_at', now)
        .order('scheduled_at', ascending: true);
    return (res as List).map((e) => ScheduledMessage.fromJson(e)).toList();
  }

  /// Delete a due message after it has been sent.
  static Future<void> removeAfterSend(String id) async {
    await _client.from('scheduled_messages').delete().eq('id', id);
  }
}
