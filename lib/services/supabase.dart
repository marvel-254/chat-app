import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/profile.dart';

class Supa {
  static SupabaseClient get client => Supabase.instance.client;

  // Auth
  static Future<AuthResponse> signUp(String email, String password, String username) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
    if (res.user != null) {
      await client.from('profiles').insert({
        'id': res.user!.id,
        'username': username,
        'display_name': username,
      });
    }
    return res;
  }

  static Future<AuthResponse> signIn(String email, String password) =>
      client.auth.signInWithPassword(email: email, password: password);

  static Future<void> signOut() => client.auth.signOut();
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // Re-send the email confirmation link for an unconfirmed account.
  static Future<void> resendConfirmation(String email) =>
      client.auth.resend(type: OtpType.signup, email: email);

  // Profiles
  static Future<Profile?> getProfile(String uid) async {
    final res = await client.from('profiles').select().eq('id', uid).maybeSingle();
    return res != null ? Profile.fromJson(res) : null;
  }

  static Future<Profile?> getProfileByUsername(String username) async {
    final res = await client.from('profiles').select().eq('username', username).maybeSingle();
    return res != null ? Profile.fromJson(res) : null;
  }

  static Future<List<Profile>> searchUsers(String query, {int limit = 20}) async {
    final res = await client.from('profiles').select().ilike('username', '%$query%').limit(limit);
    return (res as List).map((e) => Profile.fromJson(e)).toList();
  }

  // Conversations
  static Future<Conversation> getOrCreateDM(String otherUid) async {
    final me = currentUser!.id;
    final existing = await client.rpc('get_or_create_dm', params: {'my_id': me, 'other_id': otherUid});
    final convId = existing as String;
    return Conversation(id: convId, createdAt: DateTime.now(), updatedAt: DateTime.now());
  }

  static Stream<List<Conversation>> watchConversations() {
    final me = currentUser!.id;
    return client
        .from('conversation_participants')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('user_id', me)
        .map((rows) async {
          final convIds = rows.map((r) => r['conversation_id'] as String).toList();
          if (convIds.isEmpty) return <Conversation>[];
          final res = await client.rpc(
            'get_conversations_for_user',
          );
          final rows2 = (res as List).cast<Map<String, dynamic>>();
          return rows2.map((r) => Conversation(
                id: r['conversation_id'] as String,
                createdAt: DateTime.parse(r['created_at'] as String),
                updatedAt: DateTime.parse(r['updated_at'] as String),
                peerId: r['peer_id'] as String?,
                peerUsername: r['peer_username'] as String?,
                peerDisplayName: r['peer_display_name'] as String?,
                lastMessage: r['last_message'] as String?,
                lastMessageAt: r['last_message_at'] == null
                    ? null
                    : DateTime.parse(r['last_message_at'] as String),
                unreadCount: (r['unread_count'] as num?)?.toInt() ?? 0,
              )).toList();
        })
        .asyncExpand((f) => Stream.fromFuture(f));
  }

  // Messages
  static Stream<List<Message>> watchMessages(String conversationId) {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map((r) => Message.fromJson(r)).toList());
  }

  static Future<Message> sendMessage(String conversationId, String content) async {
    final me = currentUser!.id;
    final msgId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    await client.from('messages').insert({
      'id': msgId,
      'conversation_id': conversationId,
      'sender_id': me,
      'content': content,
      'created_at': now,
    });
    await client.from('conversations').update({'updated_at': now}).eq('id', conversationId);
    return Message(
      id: msgId,
      conversationId: conversationId,
      senderId: me,
      content: content,
      createdAt: DateTime.parse(now),
    );
  }

  static Future<void> markRead(String conversationId, String messageId) async {
    await client.from('messages').update({'read_at': DateTime.now().toIso8601String()}).eq('id', messageId);
    await client
        .from('conversation_participants')
        .update({'last_read_at': DateTime.now().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', currentUser!.id);
  }

  // Realtime typing broadcast.
  // Broadcasts typing status on a per-conversation channel so the peer can
  // see "Typing…". Uses a short-lived broadcast event (no persistence).
  static const _typingEvent = 'typing';

  static String _typingTopic(String conversationId) => 'typing:$conversationId';
  static final Map<String, RealtimeChannel> _typingChannels = {};

  static Future<void> broadcastTyping(String conversationId, bool isTyping) async {
    final channel = _typingChannels[conversationId];
    if (channel == null) return;
    await channel
        .httpSend(
          event: _typingEvent,
          payload: {
            'user_id': currentUser?.id,
            'is_typing': isTyping,
          },
        )
        .catchError((_) {}); // never throw on a best-effort typing signal
  }

  /// Subscribe to typing broadcasts for a conversation. Invokes [onTyping]
  /// with the sender's user id and whether they are typing.
  static void onTyping(String conversationId, void Function(String userId, bool isTyping) onTyping) {
    final previous = _typingChannels.remove(conversationId);
    if (previous != null) client.removeChannel(previous);

    final channel = client.channel(_typingTopic(conversationId));
    _typingChannels[conversationId] = channel;
    channel
        .onBroadcast(
          event: _typingEvent,
          callback: (payload) {
            final uid = payload['user_id'] as String?;
            final typing = payload['is_typing'] as bool? ?? false;
            if (uid != null) onTyping(uid, typing);
          },
        )
        .subscribe();
  }

  static void unsubscribeTyping(String conversationId) {
    final channel = _typingChannels.remove(conversationId);
    if (channel != null) client.removeChannel(channel);
  }
}