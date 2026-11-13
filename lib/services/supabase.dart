import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/profile.dart';
import 'search_safety.dart';

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
    var body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['error'] as String? ??
          "We couldn't upload that file. Please try again.");
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
    final term = sanitizeSearchTerm(query);
    if (term.isNotEmpty) {
      request = request.or('username.ilike.%$term%,display_name.ilike.%$term%');
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

  static String _intervalLiteral(Duration? value) {
    if (value == null || value == Duration.zero) return '0 seconds';
    return '${value.inSeconds} seconds';
  }

  static Future<void> updateProfileDetails(
      {required String about,
      required String photoVisibility,
      required String statusVisibility,
      required String aboutVisibility,
      bool readReceiptsEnabled = true,
      Duration? defaultMessageExpiry,
      Duration? autoLockTimer}) async {
    await client.from('profiles').update({
      'about': about.trim().isEmpty ? null : about.trim(),
      'photo_visibility': photoVisibility,
      'status_visibility': statusVisibility,
      'about_visibility': aboutVisibility,
      'read_receipts_enabled': readReceiptsEnabled,
      'default_message_expiry': _intervalLiteral(defaultMessageExpiry),
      'auto_lock_timer': _intervalLiteral(autoLockTimer),
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
      final term = sanitizeSearchTerm(search ?? '');
      if (term.isNotEmpty) {
        profileQuery = profileQuery.or(
            'username.ilike.%$term%,display_name.ilike.%$term%');
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
      final term = sanitizeSearchTerm(search ?? '');
      if (term.isNotEmpty) {
        profileQuery = profileQuery.or(
            'username.ilike.%$term%,display_name.ilike.%$term%');
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

  static Future<String> uploadStatusMedia(
      Uint8List bytes, String filename) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Status photos must be 5 MB or smaller.');
    }
    final uid = currentUser!.id;
    final extension = path.extension(filename).toLowerCase();
    final safeExt = switch (extension) {
      '.png' => '.png',
      '.webp' => '.webp',
      '.gif' => '.gif',
      _ => '.jpg',
    };
    final contentType = switch (safeExt) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    final objectPath = '$uid/status/${const Uuid().v4()}$safeExt';
    await client.storage.from('avatars').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            cacheControl: '3600',
            contentType: contentType,
          ),
        );
    return client.storage.from('avatars').getPublicUrl(objectPath);
  }

  static String? statusMediaUrl(String? mediaPath) {
    if (mediaPath == null || mediaPath.trim().isEmpty) return null;
    if (mediaPath.startsWith('http://') || mediaPath.startsWith('https://')) {
      return mediaPath;
    }
    return client.storage.from('avatars').getPublicUrl(mediaPath);
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
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Profile photos must be 5 MB or smaller.');
    }
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
    final publicUrl = client.storage.from('avatars').getPublicUrl(objectPath);
    // Cache-bust so peers and this device pick up the new object immediately.
    // peer_avatar_url is RPC output only — never write it onto participants.
    final url = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    await client.from('profiles').update({
      'avatar_url': url,
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

  // Message Requests — "contacts" means we already share a conversation.
  // There is no `contacts` table; privacy uses shares_conversation() the same way.
  static Future<bool> areContacts(String userId1, String userId2) async {
    if (userId1 == userId2) return true;
    try {
      final mine = await client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', userId1);
      final ids = (mine as List)
          .map((row) => row['conversation_id'] as String)
          .toList();
      if (ids.isEmpty) return false;
      final theirs = await client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', userId2)
          .inFilter('conversation_id', ids)
          .limit(1);
      return (theirs as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> addContact(String contactId) async {
    // Accepting a request already shares a conversation row; nothing to upsert.
    // contactId is kept so callers (acceptMessageRequest) stay unchanged.
    assert(contactId.isNotEmpty);
  }

  static Stream<List<Map<String, dynamic>>> watchMessageRequests() {
    return Stream.periodic(const Duration(seconds: 30), (_) => null)
        .asyncMap((_) async {
      final me = currentUser!.id;
      final res = await client.rpc('get_conversations_for_user');
      final rows = (res as List).cast<Map<String, dynamic>>();
      final requests = <Map<String, dynamic>>[];
      for (final r in rows) {
        final peerId = r['peer_id'] as String?;
        if (peerId != null) {
          final isContact = await areContacts(me, peerId);
          if (!isContact) {
            requests.add(r);
          }
        }
      }
      return requests;
    });
  }

  static Future<void> acceptMessageRequest(
      String conversationId, String peerId) async {
    await addContact(peerId);
  }

  static Future<void> declineMessageRequest(String conversationId) async {
    final me = currentUser!.id;
    await client
        .from('conversation_participants')
        .delete()
        .eq('conversation_id', conversationId)
        .eq('user_id', me);
  }

  static Stream<List<Conversation>> watchConversations() {
    return Stream.periodic(const Duration(seconds: 30), (_) => null)
        .asyncMap((_) async {
      final res = await client.rpc('get_conversations_for_user');
      final rows = (res as List).cast<Map<String, dynamic>>();
      return rows
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
                isLocked: (r['is_locked'] as bool?) ?? false,
              ))
          .toList();
    });
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
          final hiddenIds = <String>{};
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
              final hides = await client
                  .from('message_hides')
                  .select('message_id')
                  .eq('user_id', currentUser!.id)
                  .filter('message_id', 'in', messageIds);
              for (final row in hides as List) {
                hiddenIds.add(row['message_id'] as String);
              }
            } catch (_) {}
          }
          final now = DateTime.now();
          return rows
              .where((r) =>
                  !hiddenIds.contains(r['id'] as String) &&
                  (r['expires_at'] == null ||
                  DateTime.parse(r['expires_at'] as String).isAfter(now)))
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
      expiry: expiry,
    );
  }

  static Future<void> markRead(String conversationId, String messageId) async {
    // Use the new SECURITY DEFINER RPC that handles read receipts atomically
    await client.rpc('mark_messages_read', params: {
      'p_conversation_id': conversationId,
    });
  }

  static Future<void> updateMessage(String messageId, String content) async {
    await client
        .from('messages')
        .update({'content': content}).eq('id', messageId);
  }

  static Future<void> setMessagePinned(String messageId, bool pinned,
      {String? conversationId}) async {
    await client.rpc('pin_message', params: {
      'msg_id': messageId,
      'do_pin': pinned,
    });
  }

  static Future<void> deleteMessage(String messageId) async {
    final me = currentUser;
    if (me == null) return;
    await client.from('message_hides').upsert({
      'message_id': messageId,
      'user_id': me.id,
    }, onConflict: 'message_id,user_id');
  }

  static Future<void> deleteMessageForEveryone(String messageId) async {
    final me = currentUser;
    if (me == null) return;
    // Check if within time window (e.g., 1 hour)
    final message = await client
        .from('messages')
        .select('created_at, sender_id')
        .eq('id', messageId)
        .single();
    final senderId = message['sender_id'] as String;
    final createdAt = DateTime.parse(message['created_at'] as String);
    final now = DateTime.now().toUtc();
    final diff = now.difference(createdAt);

    if (diff > const Duration(hours: 1)) {
      // Soft delete - replace content with "This message was deleted"
      await client.from('messages').update({
        'content': 'This message was deleted',
        'edited_at': now.toIso8601String(),
      }).eq('id', messageId).eq('sender_id', senderId);
    } else {
      // Hard delete within 1 hour
      await client
          .from('messages')
          .delete()
          .eq('id', messageId)
          .eq('sender_id', senderId);
    }
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

    final channel = client.channel(_typingTopic(conversationId),
        opts: const RealtimeChannelConfig(private: true));
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
        .map((rows) => rows.toList());
  }

  // ===== Reply-to =====

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
    // Check for known URL shorteners / spam domains
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

  static String? _validateMessageContent(String content) {
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

  static Future<Message> sendMessageWithReply({
    required String conversationId,
    required String content,
    String? replyToId,
    Duration? expiry,
  }) async {
    // Anti-spam validation
    final validationError = _validateMessageContent(content);
    if (validationError != null) {
      throw StateError(validationError);
    }
    final me = currentUser!;
    final now = DateTime.now().toUtc();

    final insert = {
      'conversation_id': conversationId,
      'sender_id': me.id,
      'content': content,
      'created_at': now.toIso8601String(),
      if (replyToId != null) 'reply_to_id': replyToId,
      if (expiry != null && expiry > Duration.zero)
        'expires_at': now.add(expiry).toIso8601String(),
    };

    final res = await client.from('messages').insert(insert).select().single();

    // conversations.last_message_at is not on older schemas; a DB trigger
    // now maintains it. Never fail the send if the bump 400s.
    try {
      await client
          .from('conversations')
          .update({'updated_at': now.toIso8601String()}).eq('id', conversationId);
    } catch (_) {}

    return Message.fromJson(res);
  }

  static Future<Message?> getReplyPreview(String messageId) async {
    final res = await client
        .from('messages')
        .select('id,content,sender_id')
        .eq('id', messageId)
        .maybeSingle();
    if (res == null) return null;
    return Message.fromJson(res);
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

  // ===== Block/Report =====

  static Future<void> blockUser(String userId) async {
    final me = currentUser;
    if (me == null) return;
    await client.from('blocked_users').upsert({
      'blocker_id': me.id,
      'blocked_id': userId,
    }, onConflict: 'blocker_id,blocked_id', ignoreDuplicates: true);
  }

  static Future<void> unblockUser(String userId) async {
    final me = currentUser;
    if (me == null) return;
    await client
        .from('blocked_users')
        .delete()
        .eq('blocker_id', me.id)
        .eq('blocked_id', userId);
  }

  static Future<bool> isUserBlocked(String userId) async {
    final me = currentUser;
    if (me == null) return false;
    final res = await client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', me.id)
        .eq('blocked_id', userId)
        .maybeSingle();
    return res != null;
  }

  static Future<List<String>> getBlockedUserIds() async {
    final me = currentUser;
    if (me == null) return [];
    final res = await client
        .from('blocked_users')
        .select('blocked_id')
        .eq('blocker_id', me.id);
    return (res as List).map((e) => e['blocked_id'] as String).toList();
  }

  static Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
  }) async {
    final me = currentUser;
    if (me == null) return;
    await client.from('user_reports').insert({
      'reporter_id': me.id,
      'reported_id': userId,
      'reason': reason,
      'details': details,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

}
