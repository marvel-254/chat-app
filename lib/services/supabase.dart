import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/profile.dart';

class Supa {
  static SupabaseClient get client => Supabase.instance.client;
  static const _cloudStorageUrl = String.fromEnvironment(
    'CLOUD_STORAGE_URL',
    defaultValue: 'https://bro-chat-storage.twistedoliver211fs.workers.dev',
  );

  static Map<String, String> get _storageHeaders => {
        'Authorization': 'Bearer ${client.auth.currentSession!.accessToken}',
      };

  static Future<Map<String, dynamic>> _storagePost(String path,
      {Map<String, String>? query,
      List<int>? bytes,
      String? contentType}) async {
    final uri =
        Uri.parse('$_cloudStorageUrl$path').replace(queryParameters: query);
    final response = await http.post(uri,
        headers: {
          ..._storageHeaders,
          if (contentType != null) 'Content-Type': contentType,
        },
        body: bytes);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error'] as String? ??
          'Cloud storage request failed (${response.statusCode}).');
    }
    return body;
  }

  // Auth
  static Future<AuthResponse> signUp(
      String email, String password, String username) async {
    // The profile row is created by the on_auth_user_created database
    // trigger (migration 20261031000000_profile_creation_trigger.sql), which
    // also runs for confirmation-required sign-ups where no session exists
    // yet (#43). Do NOT insert from the client: with a null session the
    // INSERT is rejected by RLS (42501) and aborts the whole sign-up flow.
    return client.auth.signUp(
      email: email,
      password: password,
      data: {'username': username},
    );
  }

  static Future<AuthResponse> signIn(String email, String password) =>
      client.auth.signInWithPassword(email: email, password: password);

  static Future<void> signOut() => client.auth.signOut();
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges =>
      client.auth.onAuthStateChange;

  // Re-send the email confirmation link for an unconfirmed account.
  static Future<void> resendConfirmation(String email) =>
      client.auth.resend(type: OtpType.signup, email: email);

  // Profiles
  static Future<Profile?> getProfile(String uid) async {
    final res =
        await client.from('profiles').select().eq('id', uid).maybeSingle();
    return res != null ? Profile.fromJson(res) : null;
  }

  static Future<Profile?> getProfileByUsername(String username) async {
    final res = await client
        .from('profiles')
        .select()
        .eq('username', username)
        .maybeSingle();
    return res != null ? Profile.fromJson(res) : null;
  }

  static Future<List<Profile>> searchUsers(String query,
      {int limit = 20}) async {
    var request = client.from('profiles').select();
    final me = currentUser?.id;
    if (me != null) request = request.neq('id', me);
    if (query.trim().isNotEmpty) {
      request = request.or(
          'username.ilike.%${query.trim()}%,display_name.ilike.%${query.trim()}%');
    }
    final res = await request.order('username').limit(limit);
    return (res as List).map((e) => Profile.fromJson(e)).toList();
  }

  static Future<void> updateProfile(
      {required String username, required String displayName}) async {
    await client.from('profiles').update({
      'username': username.trim(),
      'display_name': displayName.trim().isEmpty ? null : displayName.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', currentUser!.id);
    await client.auth
        .updateUser(UserAttributes(data: {'username': username.trim()}));
  }

  static Future<void> updateChatBackground(String background,
      {String? imagePath}) async {
    await client.from('profiles').update({
      'chat_background': background,
      'chat_background_image_path': imagePath,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', currentUser!.id);
  }

  static Future<String> uploadChatBackground(
      Uint8List bytes, String filename) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('Chat background images must be 10 MB or smaller.');
    }
    final extension = path.extension(filename).toLowerCase();
    final contentType = switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => throw ArgumentError('Choose a JPEG, PNG, WebP, or GIF image.'),
    };
    final objectPath =
        '${currentUser!.id}/background${extension.isEmpty ? '.jpg' : extension}';
    if (_cloudStorageUrl.isNotEmpty) {
      final uploaded = await _storagePost('/upload/background',
          bytes: bytes, contentType: contentType);
      return uploaded['path'] as String;
    } else {
      await client.storage.from('chat-backgrounds').uploadBinary(
          objectPath, bytes,
          fileOptions: FileOptions(
              contentType: contentType, upsert: true, cacheControl: '3600'));
    }
    return objectPath;
  }

  static Future<String> chatBackgroundUrl(String objectPath) async {
    if (_cloudStorageUrl.isNotEmpty) {
      return (await _storagePost('/sign', query: {'key': objectPath}))['url']
          as String;
    }
    return client.storage
        .from('chat-backgrounds')
        .createSignedUrl(objectPath, 3600);
  }

  static Future<String> uploadAvatar(Uint8List bytes, String filename) async {
    final uid = currentUser!.id;
    final extension = path.extension(filename).toLowerCase();
    final objectPath = '$uid/avatar${extension.isEmpty ? '.jpg' : extension}';
    final contentType = switch (extension) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      '.heic' => 'image/heic',
      '.heif' => 'image/heif',
      _ => 'image/jpeg',
    };
    await client.storage.from('avatars').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
              upsert: true, cacheControl: '3600', contentType: contentType),
        );
    final url = client.storage.from('avatars').getPublicUrl(objectPath);
    await client.from('profiles').update({
      'avatar_url': '$url?v=${DateTime.now().millisecondsSinceEpoch}',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', uid);
    return url;
  }

  static Future<Map<String, dynamic>> uploadAttachment(String conversationId,
      Uint8List bytes, String filename, String mimeType) async {
    final uid = currentUser!.id;
    final id = const Uuid().v4();
    final safeName =
        path.basename(filename).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    var objectPath = '$conversationId/$uid/$id-$safeName';
    if (_cloudStorageUrl.isNotEmpty) {
      final uploaded = await _storagePost('/upload/attachment',
          query: {'conversation': conversationId, 'name': safeName},
          bytes: bytes,
          contentType: mimeType);
      objectPath = uploaded['path'] as String;
    } else {
      await client.storage.from('chat-files').uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
    }
    return {
      'kind': mimeType.startsWith('image/')
          ? 'image'
          : (mimeType.startsWith('video/') ? 'video' : 'file'),
      'name': filename,
      'path': objectPath,
      'mime': mimeType,
      'size': bytes.length,
    };
  }

  static Future<String> attachmentUrl(String objectPath) async {
    if (_cloudStorageUrl.isNotEmpty) {
      return (await _storagePost('/sign', query: {'key': objectPath}))['url']
          as String;
    }
    return client.storage.from('chat-files').createSignedUrl(objectPath, 3600);
  }

  // Conversations
  static Future<Conversation> getOrCreateDM(String otherUid) async {
    final me = currentUser!.id;
    final existing = await client
        .rpc('get_or_create_dm', params: {'my_id': me, 'other_id': otherUid});
    final convId = existing as String;
    return Conversation(
        id: convId, createdAt: DateTime.now(), updatedAt: DateTime.now());
  }

  static Stream<List<Conversation>> watchConversations() {
    final me = currentUser!.id;
    return client
        .from('conversation_participants')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('user_id', me)
        .map((rows) async {
          final convIds =
              rows.map((r) => r['conversation_id'] as String).toList();
          if (convIds.isEmpty) return <Conversation>[];
          final res = await client.rpc(
            'get_conversations_for_user',
          );
          final rows2 = (res as List).cast<Map<String, dynamic>>();
          return rows2
              .map((r) => Conversation(
                    id: r['conversation_id'] as String,
                    createdAt: DateTime.parse(r['created_at'] as String),
                    updatedAt: DateTime.parse(r['updated_at'] as String),
                    peerId: r['peer_id'] as String?,
                    peerUsername: r['peer_username'] as String?,
                    peerDisplayName: r['peer_display_name'] as String?,
                    peerAvatarUrl: r['peer_avatar_url'] as String?,
                    lastMessage: r['last_message'] as String?,
                    lastMessageAt: r['last_message_at'] == null
                        ? null
                        : DateTime.parse(r['last_message_at'] as String),
                    unreadCount: (r['unread_count'] as num?)?.toInt() ?? 0,
                  ))
              .toList();
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

  static Future<Message> sendMessage(
      String conversationId, String content) async {
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
    await client
        .from('conversations')
        .update({'updated_at': now}).eq('id', conversationId);
    return Message(
      id: msgId,
      conversationId: conversationId,
      senderId: me,
      content: content,
      createdAt: DateTime.parse(now),
    );
  }

  static Future<void> markRead(String conversationId, String messageId) async {
    await client.from('messages').update(
        {'read_at': DateTime.now().toIso8601String()}).eq('id', messageId);
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

  static Future<void> broadcastTyping(
      String conversationId, bool isTyping) async {
    final channel = _typingChannels[conversationId];
    if (channel == null) return;
    await channel.httpSend(
      event: _typingEvent,
      payload: {
        'user_id': currentUser?.id,
        'is_typing': isTyping,
      },
    ).catchError((_) {}); // never throw on a best-effort typing signal
  }

  /// Subscribe to typing broadcasts for a conversation. Invokes [onTyping]
  /// with the sender's user id and whether they are typing.
  static void onTyping(String conversationId,
      void Function(String userId, bool isTyping) onTyping) {
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
