import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import 'legacy_message_codec.dart';
import 'legacy_messaging.dart';

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
  /// This is the explicitly opted-in, server-readable legacy transport.
  static Future<Message> send({
    required String conversationId,
    required String content,
    String? messageId,
    String? validationContent,
    String contentFormat = LegacyMessageCodec.plaintext,
    String? replyToId,
    Duration? expiry,
    String? expectedSenderId,
  }) async {
    final me = _currentUser;
    if (me == null || (expectedSenderId != null && me.id != expectedSenderId)) {
      throw StateError('The sender is no longer signed in.');
    }
    final validationError = validateContent(validationContent ?? content);
    if (validationError != null) {
      throw StateError(validationError);
    }
    final now = DateTime.now().toUtc();

    if (contentFormat != LegacyMessageCodec.signal) {
      LegacyMessaging.requireAllowed(me.id);
    }

    final insert = {
      if (messageId != null) 'id': messageId,
      'conversation_id': conversationId,
      'sender_id': me.id,
      'content': content,
      'content_format': contentFormat,
      'created_at': now.toIso8601String(),
      if (replyToId != null) 'reply_to_id': replyToId,
      if (expiry != null && expiry > Duration.zero)
        'expires_at': now.add(expiry).toIso8601String(),
    };

    final res = await _client.from('messages').insert(insert).select().single();

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
        .select(
            'id,content,content_format,sender_id,conversation_id,created_at')
        .eq('id', messageId)
        .maybeSingle();
    if (res == null) return null;
    return Message.fromJson(res);
  }
}
