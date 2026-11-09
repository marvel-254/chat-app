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

  static Future<void> savePushToken(
      String firebaseInstallationId, String platform) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('push_tokens').upsert(
      {
        'user_id': user.id,
        'firebase_installation_id': firebaseInstallationId,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'firebase_installation_id',
    );
  }

  static Future<void> removePushToken(String firebaseInstallationId) async {
    final user = currentUser;
    if (user == null) return;
    await client
        .from('push_tokens')
        .delete()
        .eq('user_id', user.id)
        .eq('firebase_installation_id', firebaseInstallationId);
  }

  // Re-send the email confirmation link for an unconfirmed account.
  static Future<void> resendConfirmation(String email) =>
      client.auth.resend(type: OtpType.signup, email: email);

  // Profiles
  static Future<Profile?> getProfile(String uid) async {
    final res =
        await client.from('visible_profiles').select().eq('id', uid).maybeSingle();
    return res != null ? Profile.fromJson(res) : null;
  }

  static Future<Profile?> getProfileByUsername(String username) async {
    final res = await client
        .from('visible_profiles')
        .select()
        .eq('username', username)
        .maybeSingle();
    return res != null ? Profile.fromJson(res) : null;
  }

  static Future<List<Profile>> searchUsers(String query,
      {int limit = 20}) async {
    var request = client.from('visible_profiles').select();
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

  static Future<void> updateProfileDetails(
      {required String about,
      required String photoVisibility,
      required String statusVisibility,
      required String aboutVisibility,
      bool readReceiptsEnabled = true,
      Duration? defaultMessageExpiry}) async {
    await client.from('profiles').update({
      'about': about.trim().isEmpty ? null : about.trim(),
      'photo_visibility': photoVisibility,
      'status_visibility': statusVisibility,
      'about_visibility': aboutVisibility,
      'read_receipts_enabled': readReceiptsEnabled,
      'default_message_expiry': defaultMessageExpiry == null ||
              defaultMessageExpiry == Duration.zero
          ? '0 seconds'
          : '${defaultMessageExpiry.inSeconds} seconds',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', currentUser!.id);
  }

  static Future<void> recordLastSeen() async {
    try {
      await client.rpc('record_last_seen');
    } catch (_) {}
  }

  static Future<bool> isFollowing(String userId) async {
    final row = await client
        .from('user_follows')
        .select('followed_id')
        .eq('follower_id', currentUser!.id)
        .eq('followed_id', userId)
        .maybeSingle();
    return row != null;
  }

  static Future<void> setFollowing(String userId, bool follow) async {
    if (follow) {
      await client.from('user_follows').upsert(
          {'follower_id': currentUser!.id, 'followed_id': userId},
          onConflict: 'follower_id,followed_id',
          ignoreDuplicates: true);
    } else {
      await client
          .from('user_follows')
          .delete()
          .eq('follower_id', currentUser!.id)
          .eq('followed_id', userId);
    }
  }

  static Future<int> getFollowersCount(String userId) async {
    try {
      final res = await client
          .from('user_follows')
          .select('follower_id')
          .eq('followed_id', userId);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> getFollowingCount(String userId) async {
    try {
      final res = await client
          .from('user_follows')
          .select('followed_id')
          .eq('follower_id', userId);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Profile>> getFollowers(String userId,
      {int? limit, int? offset, String? search}) async {
    try {
      var query = client
          .from('user_follows')
          .select('follower_id')
          .eq('followed_id', userId) as dynamic;

      if (offset != null && offset > 0) {
        query = query.range(offset, offset + (limit ?? 30) - 1);
      } else if (limit != null) {
        query = query.limit(limit);
      }

      final res = await query;
      final ids =
          (res as List).map((row) => row['follower_id'] as String).toList();
      if (ids.isEmpty) return [];

      var profileQuery = client.from('visible_profiles').select().filter('id', 'in', ids) as dynamic;
      if (search != null && search.isNotEmpty) {
        profileQuery = profileQuery.or('username.ilike.%$search%,label.ilike.%$search%');
      }
      final profs = await profileQuery;
      return (profs as List)
          .map((p) => Profile.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Profile>> getFollowing(String userId,
      {int? limit, int? offset, String? search}) async {
    try {
      var query = client
          .from('user_follows')
          .select('followed_id')
          .eq('follower_id', userId) as dynamic;

      if (offset != null && offset > 0) {
        query = query.range(offset, offset + (limit ?? 30) - 1);
      } else if (limit != null) {
        query = query.limit(limit);
      }

      final res = await query;
      final ids =
          (res as List).map((row) => row['followed_id'] as String).toList();
      if (ids.isEmpty) return [];

      var profileQuery = client.from('visible_profiles').select().filter('id', 'in', ids) as dynamic;
      if (search != null && search.isNotEmpty) {
        profileQuery = profileQuery.or('username.ilike.%$search%,label.ilike.%$search%');
      }
      final profs = await profileQuery;
      return (profs as List)
          .map((p) => Profile.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Statuses
  static Future<void> createStatus({
    String? content,
    String? mediaPath,
    String? mood,
    String privacy = 'contacts',
  }) async {
    await client.from('statuses').insert({
      'user_id': currentUser!.id,
      if (content != null && content.trim().isNotEmpty)
        'content': content.trim(),
      if (mediaPath != null) 'media_path': mediaPath,
      if (mood != null && mood.trim().isNotEmpty) 'mood': mood.trim(),
      'privacy': privacy,
    });
  }

  static Stream<List<StatusPost>> watchStatuses() {
    return client
        .from('statuses')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          final now = DateTime.now();
          final activeRows = rows.where((r) {
            final exp = DateTime.tryParse(r['expires_at'] as String? ?? '');
            return exp != null && exp.isAfter(now);
          }).toList();
          final userIds =
              activeRows.map((r) => r['user_id'] as String).toSet().toList();
          final profilesMap = <String, Map<String, dynamic>>{};
          if (userIds.isNotEmpty) {
            final profs =
                await client.from('visible_profiles').select().filter('id', 'in', userIds);
            for (final p in profs as List) {
              profilesMap[p['id'] as String] = p as Map<String, dynamic>;
            }
          }
          return activeRows.map((r) {
            final rowWithProfile = Map<String, dynamic>.from(r);
            rowWithProfile['profiles'] = profilesMap[r['user_id']];
            return StatusPost.fromJson(rowWithProfile);
          }).toList();
        });
  }

  static Future<void> deleteStatus(String statusId) async {
    await client.from('statuses').delete().eq('id', statusId);
  }

  // Conversation lock
  static Future<bool> isConversationLocked(String conversationId) async {
    final me = currentUser;
    if (me == null) return false;
    final res = await client
        .from('conversation_locks')
        .select('conversation_id')
        .eq('conversation_id', conversationId)
        .eq('user_id', me.id)
        .maybeSingle();
    return res != null;
  }

  static Future<void> setConversationLocked(
      String conversationId, bool locked) async {
    final me = currentUser;
    if (me == null) return;
    if (locked) {
      await client.from('conversation_locks').upsert({
        'conversation_id': conversationId,
        'user_id': me.id,
      }, onConflict: 'conversation_id,user_id');
    } else {
      await client
          .from('conversation_locks')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', me.id);
    }
  }

  static Future<void> updateChatBackground(String background,
      {String? imagePath}) async {
    await client.from('profiles').update({
      'chat_background': background,
      'chat_background_image_path': imagePath,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', currentUser!.id);
  }

  static Future<void> refreshConversations() async {
    await client
        .from('conversation_participants')
        .select('conversation_id')
        .eq('user_id', currentUser!.id);
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
    final rows = await client
        .from('conversation_participants')
        .select('conversation_id')
        .eq('user_id', uid);
    for (final row in rows) {
      await client
          .from('conversation_participants')
          .update({'peer_avatar_url': url})
          .eq('conversation_id', row['conversation_id'] as String);
    }
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

    try {
      final myProfile = await getProfile(me);
      if (myProfile != null &&
          myProfile.defaultMessageExpiry != null &&
          myProfile.defaultMessageExpiry! > Duration.zero) {
        final currentExp = await getMessageExpiry(convId);
        if (currentExp == null || currentExp == Duration.zero) {
          await setMessageExpiry(convId, myProfile.defaultMessageExpiry);
        }
      }
    } catch (_) {}

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

          final lockedSet = <String>{};
          try {
            final locks = await client
                .from('conversation_locks')
                .select('conversation_id')
                .eq('user_id', me);
            for (final l in locks as List) {
              lockedSet.add(l['conversation_id'] as String);
            }
          } catch (_) {}

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
                    isLocked: lockedSet.contains(r['conversation_id'] as String),
                  ))
              .toList();
        })
        .asyncExpand((f) => Stream.fromFuture(f));
  }

  // Messages
  static Stream<List<Message>> watchMessages(String conversationId) {
    return client
        .from('messages')
        .stream(
          primaryKey: ['id'],
        )
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .asyncMap((rows) async {
          final messageIds = rows.map((r) => r['id'] as String).toList();
          final readByPeerSet = <String>{};
          final reactionsMap = <String, List<Map<String, dynamic>>>{};
          if (messageIds.isNotEmpty && currentUser != null) {
            try {
              final reads = await client
                  .from('message_reads')
                  .select('message_id')
                  .filter('message_id', 'in', messageIds)
                  .neq('user_id', currentUser!.id);
              for (final row in reads as List) {
                readByPeerSet.add(row['message_id'] as String);
              }
              // Fetch reactions for all messages in batch
              final reactions = await client
                  .from('message_reactions')
                  .select('message_id,emoji,user_id,created_at')
                  .filter('message_id', 'in', messageIds);
              for (final row in reactions as List) {
                final mid = row['message_id'] as String;
                reactionsMap.putIfAbsent(mid, () => []).add(row);
              }
            } catch (_) {}
          }
          final now = DateTime.now();
          return rows
              .where((r) =>
                  r['expires_at'] == null ||
                  DateTime.parse(r['expires_at'] as String).isAfter(now))
              .map((r) {
                final id = r['id'] as String;
                final msg = Message.fromJson(r);
                return Message(
                  id: msg.id,
                  conversationId: msg.conversationId,
                  senderId: msg.senderId,
                  content: msg.content,
                  createdAt: msg.createdAt,
                  readAt: msg.readAt,
                  expiresAt: msg.expiresAt,
                  pinnedAt: msg.pinnedAt,
                  editedAt: msg.editedAt,
                  originalContent: msg.originalContent,
                  readByPeer: readByPeerSet.contains(id) || msg.readAt != null,
                  replyToId: msg.replyToId,
                  reactions: reactionsMap[id] ?? [],
                );
              })
              .toList();
        });
  }

  static Future<Message> sendMessage(String conversationId, String content,
      {Duration? expiry, String? replyToId}) async {
    return sendMessageWithReply(
      conversationId: conversationId,
      content: content,
      replyToId: replyToId,
    );
  }

  static Future<void> markRead(String conversationId, String messageId) async {
    final me = currentUser;
    if (me != null) {
      try {
        final profile = await getProfile(me.id);
        if (profile == null || profile.readReceiptsEnabled) {
          await client.from('message_reads').upsert({
            'message_id': messageId,
            'user_id': me.id,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'message_id,user_id', ignoreDuplicates: true);
        }
      } catch (_) {}
    }
    await client
        .from('conversation_participants')
        .update({'last_read_at': DateTime.now().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', currentUser!.id);
  }

  static Future<void> updateMessage(String messageId, String content) async {
    await client
        .from('messages')
        .update({'content': content}).eq('id', messageId);
  }

  static Future<void> setMessagePinned(String messageId, bool pinned,
      {String? conversationId}) async {
    if (pinned && conversationId != null) {
      final res = await client
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .not('pinned_at', 'is', null);
      if ((res as List).length >= 5) {
        throw StateError('You can pin up to 5 messages per conversation.');
      }
    }
    await client.from('messages').update({
      'pinned_at': pinned ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', messageId);
  }

  static Future<void> setMessageExpiry(
      String conversationId, Duration? expiry) async {
    await client.from('conversations').update({
      'message_expiry': expiry == null || expiry == Duration.zero
          ? '0 seconds'
          : '${expiry.inSeconds} seconds',
    }).eq('id', conversationId);
  }

  static Future<Duration?> getMessageExpiry(String conversationId) async {
    final row = await client
        .from('conversations')
        .select('message_expiry')
        .eq('id', conversationId)
        .single();
    final raw = row['message_expiry'] as String? ?? '00:00:00';
    final days = RegExp(r'(\d+(?:\.\d+)?)\s+days?').firstMatch(raw);
    if (days != null) {
      final duration =
          Duration(seconds: ((double.parse(days.group(1)!) * 86400).round()));
      return duration == Duration.zero ? null : duration;
    }
    final parts = raw.split(':');
    if (parts.length != 3) return null;
    final seconds = double.tryParse(parts[2]) ?? 0;
    final duration = Duration(
        hours: int.tryParse(parts[0]) ?? 0,
        minutes: int.tryParse(parts[1]) ?? 0,
        seconds: seconds.floor());
    return duration == Duration.zero ? null : duration;
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

  // Presence / last seen

  /// Returns true if [userId] is currently online (last_seen_at within 2 min
  /// and statusVisibility is not 'nobody').
  static Future<bool> isPeerOnline(String userId) async {
    final result = await _fetchPresence(userId);
    return result == 'online';
  }

  /// Streams a human-readable presence string for [userId] every 30 seconds.
  /// Returns null when the user has opted out (statusVisibility == 'nobody'),
  /// or 'online' / 'last seen …' otherwise.
  /// The current user's own statusVisibility is NOT applied here — the peer's
  /// preference is what controls visibility for everyone else.
  static Stream<String?> watchPeerPresence(String userId) async* {
    yield await _fetchPresence(userId);
    yield* Stream.periodic(const Duration(seconds: 30))
        .asyncMap((_) => _fetchPresence(userId));
  }

  static Future<String?> _fetchPresence(String userId) async {
    try {
      final row = await client
          .from('visible_profiles')
          .select('last_seen_at, status_visibility')
          .eq('id', userId)
          .single();
      final visibility = row['status_visibility'] as String? ?? 'everyone';
      if (visibility == 'nobody') return null;
      // 'contacts' — peer is a DM contact if a conversation exists; treat as
      // visible for simplicity (full enforcement requires server-side check).
      final raw = row['last_seen_at'] as String?;
      if (raw == null) return null;
      final lastSeen = DateTime.parse(raw).toLocal();
      return formatLastSeen(lastSeen);
    } catch (_) {
      return null;
    }
  }

  /// Returns 'online' if [lastSeen] is within the last 2 minutes, otherwise
  /// a human-readable "last seen …" string.
  static String formatLastSeen(DateTime lastSeen) {
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 2) return 'online';
    if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) {
      final h = lastSeen.hour == 0
          ? 12
          : (lastSeen.hour > 12 ? lastSeen.hour - 12 : lastSeen.hour);
      final m = lastSeen.minute.toString().padLeft(2, '0');
      final ap = lastSeen.hour >= 12 ? 'PM' : 'AM';
      return 'last seen today at $h:$m $ap';
    }
    if (diff.inDays == 1) return 'last seen yesterday';
    if (diff.inDays < 7) return 'last seen ${diff.inDays} days ago';
    return 'last seen ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
  }

  // ===== Reactions =====

  static Future<void> addReaction(String messageId, String emoji) async {
    final me = currentUser;
    if (me == null) return;
    await client.from('message_reactions').upsert({
      'message_id': messageId,
      'user_id': me.id,
      'emoji': emoji,
    }, onConflict: 'message_id,user_id,emoji', ignoreDuplicates: true);
  }

  static Future<void> removeReaction(String messageId, String emoji) async {
    final me = currentUser;
    if (me == null) return;
    await client
        .from('message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', me.id)
        .eq('emoji', emoji);
  }

  static Future<List<Map<String, dynamic>>> getReactions(String messageId) async {
    final res = await client
        .from('message_reactions')
        .select('emoji,user_id,created_at')
        .eq('message_id', messageId)
        .order('created_at', ascending: true);
    return (res as List).cast<Map<String, dynamic>>();
  }

  static Stream<List<Map<String, dynamic>>> watchReactions(String messageId) {
    return client
        .from('message_reactions')
        .stream(primaryKey: ['id'])
        .eq('message_id', messageId)
        .map((rows) => rows.map((r) => r as Map<String, dynamic>).toList());
  }

  // ===== Reply-to =====

  static Future<Message> sendMessageWithReply({
    required String conversationId,
    required String content,
    String? replyToId,
  }) async {
    final me = currentUser!;
    final now = DateTime.now().toUtc().toIso8601String();

    final insert = {
      'conversation_id': conversationId,
      'sender_id': me.id,
      'content': content,
      'created_at': now,
      if (replyToId != null) 'reply_to_id': replyToId,
    };

    final res = await client
        .from('messages')
        .insert(insert)
        .select()
        .single();

    final msg = Message.fromJson(res as Map<String, dynamic>);

    // Update conversation last_message_at
    await client
        .from('conversations')
        .update({'last_message_at': now})
        .eq('id', conversationId);

    return msg;
  }

  static Future<Message?> getReplyPreview(String messageId) async {
    final res = await client
        .from('messages')
        .select('id,content,sender_id')
        .eq('id', messageId)
        .maybeSingle();
    if (res == null) return null;
    return Message.fromJson(res as Map<String, dynamic>);
  }

  // ===== Read Receipts (enhanced) =====

  static Future<bool> getReadReceiptsEnabled() async {
    final me = currentUser;
    if (me == null) return true;
    final profile = await getProfile(me.id);
    return profile?.readReceiptsEnabled ?? true;
  }

  static Future<void> setReadReceiptsEnabled(bool enabled) async {
    final me = currentUser;
    if (me == null) return;
    await client
        .from('profiles')
        .update({'read_receipts_enabled': enabled})
        .eq('id', me.id);
  }

  static Future<void> markReadWithReceipts(String conversationId,
      String messageId) async {
    final me = currentUser;
    if (me == null) return;

    // Check if read receipts are enabled
    final profile = await getProfile(me.id);
    final receiptsEnabled = profile?.readReceiptsEnabled ?? true;

    if (receiptsEnabled) {
      await client.from('message_reads').upsert({
        'message_id': messageId,
        'user_id': me.id,
        'read_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'message_id,user_id', ignoreDuplicates: true);
    }

    // Always update conversation participant's last_read_at for unread count
    await client
        .from('conversation_participants')
        .update({'last_read_at': DateTime.now().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', me.id);
  }
}
