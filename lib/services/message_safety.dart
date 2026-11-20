import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import 'package:uuid/uuid.dart';
import 'e2ee.dart';

/// Message validation, rate limiting, and send operations.
///
/// Handles anti-spam checks (rate limits, suspicious links, max length)
/// and the actual message insert with optional reply-to and expiry.
class MessageSafety {
  MessageSafety._();

  static SupabaseClient get _client => Supabase.instance.client;
  static User? get _currentUser => _client.auth.currentUser;

  // Anti-spam protection
  static DateTime? _lastMessageTime;
  static int _messageCountInWindow = 0;
  static const int _maxMessagesPerMinute = 30;
  static const int _maxMessageLength = 4000;

  static bool _checkRateLimit() {
    final now = DateTime.now();
    if (_lastMessageTime == null ||
        now.difference(_lastMessageTime!).inMinutes >= 1) {
      _lastMessageTime = now;
      _messageCountInWindow = 1;
      return true;
    }
    if (_messageCountInWindow >= _maxMessagesPerMinute) {
      return false;
    }
    _messageCountInWindow++;
    return true;
  }

  static bool _containsSuspiciousLinks(String content) {
    final suspiciousPatterns = [
      r'bit\.ly',
      r'tinyurl\.com',
      r't\.co',
      r'goo\.gl',
      r'is\.gd',
      r'v\.gd',
      r'ow\.ly',
      r'buff\.ly',
      r'adf\.ly',
      r'bc\.vc',
      r'cutt\.ly',
      r'shorte\.st',
      r'clicky\.me',
      r'tr\.im',
    ];
    for (final pattern in suspiciousPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(content)) {
        return true;
      }
    }
    return false;
  }

  /// Returns an error message if the content is invalid, or [null] if OK.
  static String? validateContent(String content) {
    if (content.trim().isEmpty) {
      return 'Write a little something before sending.';
    }
    if (content.length > _maxMessageLength) {
      return "That's a bit long — try shortening it to $_maxMessageLength characters.";
    }
    if (!_checkRateLimit()) {
      return "You're sending a bit fast. Take a breath and try again in a moment.";
    }
    if (_containsSuspiciousLinks(content)) {
      return "That message looks like it might be unsafe, so we held it back.";
    }
    return null;
  }

  /// Send a message with optional reply-to and expiry.
  /// Throws [StateError] if content fails validation.
  /// The content is encrypted end-to-end before being stored.
  static Future<Message> send({
    required String conversationId,
    required String content,
    String? replyToId,
    Duration? expiry,
    String? expectedSenderId,
    String? eventId,
  }) async {
    final me = _currentUser;
    if (me == null || (expectedSenderId != null && me.id != expectedSenderId)) {
      throw StateError('The sender is no longer signed in.');
    }
    final validationError = validateContent(content);
    if (validationError != null) {
      throw StateError(validationError);
    }
    final now = DateTime.now().toUtc();

    // Encrypt the content before storing
    final id = eventId ?? const Uuid().v4();
    final encryptedContent =
        await SecureChat.seal(id, conversationId, content, reply: replyToId);

    if (_currentUser?.id != me.id) {
      throw StateError('The sender is no longer signed in.');
    }

    final insert = {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': me.id,
      'content': encryptedContent,
      'created_at': now.toIso8601String(),
      if (replyToId != null) 'reply_to_id': replyToId,
      if (expiry != null && expiry > Duration.zero)
        'expires_at': now.add(expiry).toIso8601String(),
    };

    final res = await _client
        .from('messages')
        .upsert(insert, onConflict: 'id', ignoreDuplicates: true)
        .select()
        .maybeSingle();
    if (res == null) {
      // A prior attempt committed before its acknowledgement reached the device.
      final existing = await _client
          .from('messages')
          .select()
          .eq('id', id)
          .eq('sender_id', me.id)
          .eq('conversation_id', conversationId)
          .single();
      return Message.fromJson(existing);
    }

    // conversations.last_message_at is not on older schemas; a DB trigger
    // now maintains it. Never fail the send if the bump 400s.
    try {
      await _client.from('conversations').update(
          {'updated_at': now.toIso8601String()}).eq('id', conversationId);
    } catch (_) {}

    return Message.fromJson(res);
  }

  /// Fetch the preview of a replied-to message.
  static Future<Message?> getReplyPreview(String messageId) async {
    final res = await _client
        .from('messages')
        .select('id,content,sender_id,conversation_id,created_at')
        .eq('id', messageId)
        .maybeSingle();
    if (res == null) return null;
    return Message.fromJson(res);
  }
}
