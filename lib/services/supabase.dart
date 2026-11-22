import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/profile.dart';
import '../models/profile_theme.dart';
import 'avatar_upload.dart';
import '../models/avatar_config.dart';
import 'search_safety.dart';
import 'reactions.dart' as reactions;
import 'message_safety.dart' as message_safety;
import 'read_receipts.dart' as read_receipts;
import 'block_report.dart' as block_report;
import 'signal_e2ee.dart';
import 'legacy_message_codec.dart';
import 'legacy_messaging.dart';

class Supa {
  static SupabaseClient get client => Supabase.instance.client;
  static const _cloudStorageUrl = String.fromEnvironment(
    'CLOUD_STORAGE_URL',
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

  static Future<void> signOut() {
    LegacyMessaging.reset();
    return client.auth.signOut();
  }
  static User? get currentUser => client.auth.currentUser;
  static Stream<AuthState> get authStateChanges =>
      client.auth.onAuthStateChange;

  // Re-send the email confirmation link for an unconfirmed account.
  static Future<void> resendConfirmation(String email) =>
      client.auth.resend(type: OtpType.signup, email: email);

  // Send a password-reset email. The recovery link lands on the configured
  // site URL / deep link with a recovery session; the user can then set a
  // new password in Settings → Account (which uses updateUser).
  static Future<void> resetPasswordForEmail(String email) =>
      client.auth.resetPasswordForEmail(email.trim());

  // Profiles
  static Future<Profile?> getProfile(String uid) async {
    final res = await client
        .from('visible_profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();
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
    if (limit <= 0) return [];
    final term = sanitizeSearchTerm(query);
    // Keep the explicit empty-query behavior used by the Close Friends picker.
    if (term.isEmpty && query.trim().isNotEmpty) return [];

    var request = client.from('visible_profiles').select();
    final me = currentUser?.id;
    if (me != null) request = request.neq('id', me);
    if (term.isEmpty) {
      final rows = await request.order('username').limit(limit);
      return rows.map(Profile.fromJson).toList();
    }

    // Fetch prefixes independently so a crowded contains result cannot push
    // all username completions beyond the server-side limit. Multiword and
    // non-username queries only need the normal name search.
    final contains = request
        .or('username.ilike.%$term%,display_name.ilike.%$term%')
        .order('username')
        .limit(limit);
    final prefixTerm = term.replaceAll('_', r'\_');
    final results = await Future.wait([
      if (RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(term))
        request
            .ilike('username', '$prefixTerm%')
            .order('username')
            .limit(limit),
      contains,
    ]);
    return rankPeopleSearchResults(
      results.expand((rows) => rows.map(Profile.fromJson)),
      term,
      limit: limit,
    );
  }

  /// Ranked friend suggestions for the "People you may know" strip.
  ///
  /// The ranked RPC only returns people with mutual connections, followers,
  /// or close friends. For a fresh account (or one whose contacts are all
  /// existing DM peers) that set is empty, so fall back to the unranked
  /// "all" category, which still excludes existing DM peers.
  static Future<List<FriendSuggestion>> getFriendSuggestions(
      {int limit = 20, int offset = 0}) async {
    try {
      final res = await client.rpc('get_friend_suggestions', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      var results = (res as List)
          .map((e) => FriendSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
      debugPrint('getFriendSuggestions -> ${results.length} results');
      if (results.isEmpty && offset == 0) {
        final fallback = await client.rpc('get_friend_suggestions_by_category',
            params: {'p_category': 'all', 'p_limit': limit});
        results = (fallback as List)
            .map((e) => FriendSuggestion.fromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint(
            'getFriendSuggestions fallback -> ${results.length} results');
      }
      return results;
    } catch (e) {
      debugPrint('getFriendSuggestions failed: $e');
      rethrow;
    }
  }

  static Future<List<FriendSuggestion>> getFriendSuggestionsByCategory(
      String category,
      {int limit = 10}) async {
    try {
      final res =
          await client.rpc('get_friend_suggestions_by_category', params: {
        'p_category': category,
        'p_limit': limit,
      });
      debugPrint(
          'getFriendSuggestionsByCategory("$category") -> ${(res as List).length} results');
      return res
          .map((e) => FriendSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getFriendSuggestionsByCategory("$category") failed: $e');
      rethrow;
    }
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
      Duration? autoLockTimer,
      String? gamePlatform,
      String? gameUsername,
      String? gameStatus,
      String? gameVisibility}) async {
    final updates = <String, dynamic>{
      'about': about.trim().isEmpty ? null : about.trim(),
      'photo_visibility': photoVisibility,
      'status_visibility': statusVisibility,
      'about_visibility': aboutVisibility,
      'read_receipts_enabled': readReceiptsEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    // Only include if explicitly set (not null) to avoid overwriting with '0 seconds'
    if (defaultMessageExpiry != null) {
      updates['default_message_expiry'] =
          _intervalLiteral(defaultMessageExpiry);
    }
    if (autoLockTimer != null) {
      updates['auto_lock_timer'] = _intervalLiteral(autoLockTimer);
    }
    // Gaming fields
    if (gamePlatform != null) {
      updates['game_platform'] = gamePlatform;
    }
    if (gameUsername != null) {
      updates['game_username'] = gameUsername;
    }
    if (gameStatus != null) {
      updates['game_status'] = gameStatus;
    }
    if (gameVisibility != null) {
      updates['game_visibility'] = gameVisibility;
    }
    try {
      await client.from('profiles').update(updates).eq('id', currentUser!.id);
    } on PostgrestException catch (e) {
      // Handle case where auto_lock_timer column doesn't exist yet (pre-migration)
      if (e.code == '42703' && updates.containsKey('auto_lock_timer')) {
        // Column doesn't exist - retry without it
        updates.remove('auto_lock_timer');
        await client.from('profiles').update(updates).eq('id', currentUser!.id);
      } else {
        rethrow;
      }
    }
  }

  /// Save the gaming profile: handle, platform, current game, and visibility.
  ///
  /// Always writes all four columns (nulls included) so the editor can clear
  /// them. Callers must send a consistent set — a platform implies a handle,
  /// matching `profiles_game_username_check`.
  static Future<void> updateGameProfile({
    String? platform,
    String? username,
    String? status,
    required String visibility,
  }) async {
    final me = currentUser;
    if (me == null) return;
    await client.from('profiles').update({
      'game_platform': platform,
      'game_username': username,
      'game_status': status,
      'game_visibility': visibility,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', me.id);
  }

  static Future<void> updateProfileTheme(ProfileTheme theme) async {
    final updates = <String, dynamic>{
      ...theme.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await client.from('profiles').update(updates).eq('id', currentUser!.id);
  }

  // Digital avatar (issue #74)
  //
  // The config lives in `profiles.avatar_config` (jsonb). Reads go through a
  // SECURITY DEFINER function because `profiles` itself is not selectable by
  // clients; the function re-applies the same photo_visibility masking used by
  // the `visible_profiles` view so a hidden avatar stays hidden.
  static Future<AvatarConfig> getDigitalAvatarConfig(String uid) async {
    final res = await client.rpc('digital_avatar_config', params: {'uid': uid});
    return AvatarConfig.fromStorage(res);
  }

  static Future<void> setDigitalAvatarConfig(AvatarConfig config) async {
    await client
        .rpc('set_digital_avatar_config', params: {'cfg': config.toJson()});
  }

  static String profileMediaUrl(String objectPath) {
    if (objectPath.startsWith('http://') || objectPath.startsWith('https://')) {
      return objectPath;
    }
    return client.storage.from('profile-media').getPublicUrl(objectPath);
  }

  static Future<String> uploadProfileCover(
      Uint8List bytes, String filename) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw ArgumentError('Profile cover images must be 10 MB or smaller.');
    }
    final extension = path.extension(filename).toLowerCase();
    final contentType = switch (extension) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => throw ArgumentError('Choose a JPEG, PNG, or WebP cover image.'),
    };
    final objectPath =
        '${currentUser!.id}/cover${extension.isEmpty ? '.jpg' : extension}';
    await client.storage.from('profile-media').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            cacheControl: '3600',
            contentType: contentType,
          ),
        );
    return objectPath;
  }

  static Future<String> uploadProfileMusic(
      Uint8List bytes, String filename) async {
    if (bytes.length > 15 * 1024 * 1024) {
      throw ArgumentError('Profile music must be 15 MB or smaller.');
    }
    final extension = path.extension(filename).toLowerCase();
    final contentType = switch (extension) {
      '.mp3' => 'audio/mpeg',
      '.m4a' => 'audio/mp4',
      '.aac' => 'audio/aac',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.webm' => 'audio/webm',
      _ => throw ArgumentError(
          'Choose an MP3, M4A, AAC, WAV, OGG, or WebM audio file.'),
    };
    final objectPath =
        '${currentUser!.id}/profile-music${extension.isEmpty ? '.mp3' : extension}';
    await client.storage.from('profile-media').uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            cacheControl: '3600',
            contentType: contentType,
          ),
        );
    return objectPath;
  }

  static Future<String> uploadAnimatedAvatar(
      Uint8List bytes, String filename) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Animated avatars must be 5 MB or smaller.');
    }
    final extension = path.extension(filename).toLowerCase();
    if (extension != '.gif') {
      throw ArgumentError('Animated avatars must be GIF files.');
    }
    const objectPathSuffix = '/animated-avatar.gif';
    final objectPath = '${currentUser!.id}$objectPathSuffix';
    await client.storage.from('profile-media').uploadBinary(
          objectPath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            cacheControl: '3600',
            contentType: 'image/gif',
          ),
        );
    return objectPath;
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

  static Future<Set<String>> getFollowedUserIds(List<String> userIds) async {
    final me = currentUser?.id;
    if (me == null || userIds.isEmpty) return <String>{};
    final rows = await client
        .from('user_follows')
        .select('followed_id')
        .eq('follower_id', me)
        .inFilter('followed_id', userIds);
    return rows.map((row) => row['followed_id'] as String).toSet();
  }

  static Future<void> setFollowing(String userId, bool follow) async {
    if (follow) {
      await client.from('user_follows').upsert(
          {'follower_id': currentUser!.id, 'followed_id': userId},
          onConflict: 'follower_id,followed_id', ignoreDuplicates: true);
    } else {
      await client
          .from('user_follows')
          .delete()
          .eq('follower_id', currentUser!.id)
          .eq('followed_id', userId);
    }
  }

  static void _logUnexpected(String where, Object error) {
    debugPrint('Supa.$where failed: $error');
  }

  static Future<int> _connectionCount(String userId, String direction) async {
    try {
      final result = await client.rpc('count_user_connections', params: {
        'p_user_id': userId,
        'p_direction': direction,
      });
      return (result as num?)?.toInt() ?? 0;
    } catch (e) {
      _logUnexpected('_connectionCount', e);
      return 0;
    }
  }

  static Future<int> getFollowersCount(String userId) =>
      _connectionCount(userId, 'followers');

  static Future<int> getFollowingCount(String userId) =>
      _connectionCount(userId, 'following');

  static Future<List<Profile>> _connections(String userId, String direction,
      {int? limit, int? offset, String? search}) async {
    try {
      final rows = await client.rpc('search_user_connections', params: {
        'p_user_id': userId,
        'p_direction': direction,
        'p_search': sanitizeSearchTerm(search ?? ''),
        'p_limit': (limit ?? 30).clamp(1, 100).toInt(),
        'p_offset': (offset ?? 0).clamp(0, 100000).toInt(),
      });
      return (rows as List)
          .map((row) => Profile.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logUnexpected('_connections', e);
      return [];
    }
  }

  static Future<List<Profile>> getFollowers(String userId,
          {int? limit, int? offset, String? search}) =>
      _connections(userId, 'followers',
          limit: limit, offset: offset, search: search);

  static Future<List<Profile>> getFollowing(String userId,
          {int? limit, int? offset, String? search}) =>
      _connections(userId, 'following',
          limit: limit, offset: offset, search: search);

  static Future<List<String>> getCloseFriendIds() async {
    final me = currentUser;
    if (me == null) return [];
    final rows = await client
        .from('close_friend_members')
        .select('friend_id')
        .eq('owner_id', me.id);
    return (rows as List).map((row) => row['friend_id'] as String).toList();
  }

  static Future<void> setCloseFriend(String friendId, bool selected) async {
    final me = currentUser;
    if (me == null || me.id == friendId) return;
    if (selected) {
      await client.from('close_friend_members').upsert({
        'owner_id': me.id,
        'friend_id': friendId,
      }, onConflict: 'owner_id,friend_id');
    } else {
      await client
          .from('close_friend_members')
          .delete()
          .eq('owner_id', me.id)
          .eq('friend_id', friendId);
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
          try {
            final now = DateTime.now();
            final activeRows = rows.where((r) {
              final exp = DateTime.tryParse(r['expires_at'] as String? ?? '');
              return exp != null && exp.isAfter(now);
            }).toList();
            final userIds =
                activeRows.map((r) => r['user_id'] as String).toSet().toList();
            final profilesMap = <String, Map<String, dynamic>>{};
            if (userIds.isNotEmpty) {
              final profs = await client
                  .from('visible_profiles')
                  .select()
                  .filter('id', 'in', userIds);
              for (final p in profs as List) {
                profilesMap[p['id'] as String] = p as Map<String, dynamic>;
              }
            }
            return activeRows.map((r) {
              final rowWithProfile = Map<String, dynamic>.from(r);
              rowWithProfile['profiles'] = profilesMap[r['user_id']];
              return StatusPost.fromJson(rowWithProfile);
            }).toList();
          } catch (_) {
            // If the profile fetch fails, still return the statuses so the
            // feed never goes blank just because avatars/names are missing.
            final now = DateTime.now();
            return rows
                .where((r) {
                  final exp =
                      DateTime.tryParse(r['expires_at'] as String? ?? '');
                  return exp != null && exp.isAfter(now);
                })
                .map((r) => StatusPost.fromJson(Map<String, dynamic>.from(r)))
                .toList();
          }
        })
        // Never let a channel error kill the stream silently.
        .handleError((_) {});
  }

  /// One-shot fetch of active statuses via a plain REST query.
  /// Used where a realtime stream is overkill or unreliable (e.g. the viewer).
  static Future<List<StatusPost>> fetchStatusesOnce() async {
    final rows = await client
        .from('statuses')
        .select()
        .order('created_at', ascending: false);
    final now = DateTime.now();
    final activeRows = rows.where((r) {
      final exp = DateTime.tryParse(r['expires_at'] as String? ?? '');
      return exp != null && exp.isAfter(now);
    }).toList();
    final userIds =
        activeRows.map((r) => r['user_id'] as String).toSet().toList();
    final profilesMap = <String, Map<String, dynamic>>{};
    if (userIds.isNotEmpty) {
      try {
        final profs = await client
            .from('visible_profiles')
            .select()
            .filter('id', 'in', userIds);
        for (final p in profs as List) {
          profilesMap[p['id'] as String] = p as Map<String, dynamic>;
        }
      } catch (_) {
        // Profiles are decorative here; statuses still render without them.
      }
    }
    return activeRows.map((r) {
      final rowWithProfile = Map<String, dynamic>.from(r);
      rowWithProfile['profiles'] = profilesMap[r['user_id']];
      return StatusPost.fromJson(rowWithProfile);
    }).toList();
  }

  static Future<void> deleteStatus(String statusId) async {
    await client.from('statuses').delete().eq('id', statusId);
  }

  /// Record a view for a status (upsert to handle duplicate views gracefully)
  static Future<void> recordStatusView(String statusId) async {
    try {
      await client.from('status_views').upsert(
        {
          'status_id': statusId,
          'viewer_id': currentUser!.id,
          'viewed_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'status_id,viewer_id',
        ignoreDuplicates: true,
      );
    } catch (_) {
      // Silently fail - view tracking is best-effort
    }
  }

  /// Get view count for a status
  static Future<int> getStatusViewCount(String statusId) async {
    try {
      final res = await client
          .from('status_views')
          .select('id')
          .eq('status_id', statusId);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Get viewers for a status (for the owner)
  static Future<List<Profile>> getStatusViewers(String statusId) async {
    try {
      final rows = await client
          .from('status_views')
          .select('viewer_id')
          .eq('status_id', statusId);
      final ids = (rows as List).map((r) => r['viewer_id'] as String).toList();
      if (ids.isEmpty) return [];
      final profs = await client
          .from('visible_profiles')
          .select()
          .filter('id', 'in', ids);
      return (profs as List)
          .map((p) => Profile.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
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

  static Future<List<Conversation>> refreshConversations() =>
      fetchConversations();

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
    // Create signed URL with 1 hour expiry (fallback)
    // For longer expiry, the storage API would need a newer version
    if (_cloudStorageUrl.isNotEmpty) {
      return (await _storagePost('/sign', query: {'key': objectPath}))['url']
          as String;
    }
    return client.storage
        .from('chat-backgrounds')
        .createSignedUrl(objectPath, 3600);
  }

  static Future<String> uploadAvatar(Uint8List bytes) async {
    final uid = currentUser?.id;
    if (uid == null) throw StateError('Sign in to change your profile photo.');
    final format = await validateAvatarImage(bytes);
    if (currentUser?.id != uid) {
      throw StateError('Your session changed. Try again.');
    }

    // profiles has no SELECT grant (privacy masking lives in visible_profiles).
    final profile = await client
        .from('visible_profiles')
        .select('avatar_url')
        .eq('id', uid)
        .single();
    if (currentUser?.id != uid) {
      throw StateError('Your session changed. Try again.');
    }
    final bucket = client.storage.from('avatars');
    final previous = managedAvatarPath(
      profile['avatar_url'] as String?,
      bucket.getPublicUrl('$uid/'),
      uid,
    );
    final objectPath = '$uid/avatar-${const Uuid().v4()}.${format.extension}';
    await bucket.uploadBinary(
      objectPath,
      bytes,
      fileOptions:
          FileOptions(cacheControl: '3600', contentType: format.contentType),
    );
    final url = bucket.getPublicUrl(objectPath);
    try {
      if (currentUser?.id != uid) {
        throw StateError('Your session changed. Try again.');
      }
      // Returning the row confirms the update wasn't silently filtered by RLS.
      await client
          .from('profiles')
          .update({
            'avatar_url': url,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', uid)
          .select('id')
          .single();
    } on PostgrestException catch (error) {
      // A rejected write must not replace the existing photo. Don't delete on
      // ambiguous network errors, since the database may have committed it.
      if (currentUser?.id == uid &&
          (error.code == '42501' || error.code == 'PGRST116')) {
        unawaited(_cleanUpAvatar(objectPath));
      }
      rethrow;
    }
    if (previous != null && currentUser?.id == uid) {
      unawaited(_cleanUpAvatar(previous));
    }
    triggerConversationRefresh();
    return url;
  }

  static Future<void> _cleanUpAvatar(String objectPath) async {
    try {
      await client.storage.from('avatars').remove([objectPath]);
    } catch (_) {
      // Cleanup is best effort. It must not mask the result of the profile write.
    }
  }

  static Future<Map<String, dynamic>> uploadAttachment(String conversationId,
      Uint8List bytes, String filename, String mimeType) async {
    final uid = currentUser!.id;
    LegacyMessaging.requireAllowed(uid);
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

  /// Best-effort removal of a stored object. Callers delete the DB row first;
  /// a failed storage cleanup must never roll back the successful DB delete.
  static Future<void> deleteAttachment(String objectPath) async {
    try {
      if (_cloudStorageUrl.isNotEmpty) {
        await _storagePost('/delete', query: {'key': objectPath});
        return;
      }
      await client.storage.from('chat-files').remove([objectPath]);
    } catch (e) {
      debugPrint('deleteAttachment cleanup failed: $e');
    }
  }

  static Future<String> attachmentUrl(String objectPath) async {
    if (_cloudStorageUrl.isNotEmpty) {
      return (await _storagePost('/sign', query: {'key': objectPath}))['url']
          as String;
    }
    return client.storage.from('chat-files').createSignedUrl(objectPath, 3600);
  }

  /// Download a GIF from a URL and upload it to storage as an attachment.
  static Future<Map<String, dynamic>> uploadAttachmentFromUrl(
      String conversationId, String url, String extension) async {
    final owner = currentUser?.id;
    LegacyMessaging.requireAllowed(owner);
    final response = await http.get(Uri.parse(url));
    if (currentUser?.id != owner) throw StateError('Account changed');
    if (response.statusCode != 200) {
      throw Exception('Failed to download attachment: ${response.statusCode}');
    }
    final filename = 'download.$extension';
    return uploadAttachment(
        conversationId, response.bodyBytes, filename, 'image/$extension');
  }

  // Conversations
  static Future<List<dynamic>> fetchConversationsWithCircles() async {
    final dynamic result = await client.rpc('get_all_conversations_for_user');
    if (result is List) {
      return result.cast<dynamic>();
    }
    return [];
  }

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
    } catch (e) {
      _logUnexpected('getOrCreateDM default expiry', e);
    }

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

  static Future<List<Map<String, dynamic>>> _messageRequests() async {
    final me = currentUser!.id;
    final rows = await fetchConversationRows();
    final requests = <Map<String, dynamic>>[];
    for (final r in rows) {
      final peerId = r['peer_id'] as String?;
      if (peerId != null && !await areContacts(me, peerId)) {
        requests.add(r);
      }
    }
    return requests;
  }

  static Stream<List<Map<String, dynamic>>> watchMessageRequests() async* {
    yield await _messageRequests();
    yield* Stream.periodic(const Duration(seconds: 30))
        .asyncMap((_) => _messageRequests());
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

  static Future<List<Map<String, dynamic>>> fetchConversationRows() async {
    final res = await client.rpc('get_conversations_for_user');
    return (res as List).cast<Map<String, dynamic>>();
  }

  static List<Conversation> conversationsFromRows(
      List<Map<String, dynamic>> rows) {
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
  }

  /// Broadcast controller that triggers a conversation list refresh.
  /// Call [triggerConversationRefresh] to force an immediate refetch.
  static final _convRefreshController = StreamController<void>.broadcast();

  /// Trigger an immediate conversation list refresh.
  /// Call this after sending a message or any operation that changes
  /// the conversation list so the sender's chat list updates right away.
  static void triggerConversationRefresh() {
    _convRefreshController.add(null);
  }

  /// Internal: return a stream that emits a refetch event whenever
  /// [triggerConversationRefresh] is called or every 5 seconds as a fallback.
  static Stream<void> _conversationChanges() async* {
    // Merge manual triggers with a periodic poll (5 seconds, down from 30).
    final triggerStream = _convRefreshController.stream;
    final pollStream = Stream.periodic(const Duration(seconds: 5));

    // Simple merge using two subscriptions.
    final merged = StreamController<void>.broadcast();
    triggerStream.listen(merged.add);
    pollStream.listen((_) => merged.add(null));

    // Emit an initial event immediately so the first refetch happens right away.
    merged.add(null);
    yield* merged.stream;
  }

  // For backward compatibility
  static Future<List<Conversation>> fetchConversations() async {
    // Parse the union result into separate lists
    final dynamic result = await fetchConversationsWithCircles();
    if (result is List) {
      return result
          .whereType<Map<String, dynamic>>()
          .where((r) => !(r['is_circle'] as bool? ?? false))
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
    }
    return [];
  }

  /// Watch conversations with realtime updates.
  /// Yields immediately, then refetches whenever messages, conversations,
  /// or conversation_participants change (via Supabase Realtime).
  static Stream<List<Conversation>> watchConversations() async* {
    yield await fetchConversations();
    yield* _conversationChanges().asyncMap((_) => fetchConversations());
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
            } catch (e) {
              _logUnexpected('watchMessages enrichment', e);
            }
          }

          final now = DateTime.now();
          final visible = rows
              .where((r) =>
                  !hiddenIds.contains(r['id'] as String) &&
                  (r['expires_at'] == null ||
                      DateTime.parse(r['expires_at'] as String).isAfter(now)))
              .toList(growable: false);
          final decrypted = <String>[];
          for (final row in visible) {
            decrypted.add(await decryptForDisplay(
              row['sender_id'] as String,
              row['content'] as String,
            ));
          }
          return [
            for (var i = 0; i < visible.length; i++)
              _messageFromDecryptedRow(
                visible[i],
                decrypted[i],
                readByPeerSet,
                reactionsMap,
              )
          ];
        });
  }

  static Message _messageFromDecryptedRow(
    Map<String, dynamic> r,
    String content,
    Set<String> readByPeerSet,
    Map<String, List<Map<String, dynamic>>> reactionsMap,
  ) {
            final id = r['id'] as String;
            final msg = Message.fromJson(r);
            return Message(
              id: msg.id,
              conversationId: msg.conversationId,
              senderId: msg.senderId,
              content: content,
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
  }

  static Future<Message> sendMessage(String conversationId, String content,
      {Duration? expiry, String? replyToId, String? expectedSenderId}) async {
    return sendMessageWithReply(
      conversationId: conversationId,
      content: content,
      replyToId: replyToId,
      expiry: expiry,
      expectedSenderId: expectedSenderId,
    );
  }

  /// Mark all unread inbound messages in [conversationId] as read.
  /// Inserts read receipts into [message_reads] so the sender can see
  /// the peer has read the messages (blue double-check).
  static Future<void> markRead(String conversationId) async {
    await client.rpc('mark_messages_read', params: {
      'p_conversation_id': conversationId,
    });
  }

  static Future<void> updateMessage(String messageId, String content) async {
    final owner = currentUser?.id;
    LegacyMessaging.requireAllowed(owner);
    final current = await client.from('messages').select('content')
        .eq('id', messageId).eq('sender_id', owner!).single();
    if (currentUser?.id != owner) throw StateError('Account changed');
    if (content == current['content']) return;
    await client.from('messages').update({
      'content': content, 'content_format': LegacyMessageCodec.plaintext,
    }).eq('id', messageId).eq('sender_id', owner).select('id').single();
    if (currentUser?.id != owner) return;
    await client.from('message_edit_history').insert({
      'message_id': messageId, 'previous_content': current['content'], 'new_content': content,
    });
  }

  /// Fetch the edit history for a message.
  static Future<List<Map<String, dynamic>>> fetchEditHistory(
      String messageId) async {
    final result = await client
        .from('message_edit_history')
        .select('previous_content, new_content, edited_at')
        .eq('message_id', messageId)
        .order('edited_at', ascending: true);
    return List<Map<String, dynamic>>.from(result as List);
  }

  // The RPC derives the conversation from the message and enforces the
  // five-pin limit and author-only rule server-side.
  static Future<void> setMessagePinned(String messageId, bool pinned) async {
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
      await client
          .from('messages')
          .update({
            'content': 'This message was deleted',
            'edited_at': now.toIso8601String(),
          })
          .eq('id', messageId)
          .eq('sender_id', senderId);
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
    // Use the same parser as profile defaults: it handles `HH:MM:SS`,
    // `N days`, `N hours` and `N seconds` interval representations.
    return parseInterval(row['message_expiry']);
  }

  // ===== Drafts =====

  /// Save a draft for the current user in a conversation.
  static Future<void> saveDraft(String conversationId, String text) async {
    final me = currentUser;
    if (me == null || (text.isNotEmpty && !LegacyMessaging.allowed(me.id))) return;
    // Drafts only update an existing participation row. Inserting a row here
    // is forbidden by RLS and produced recurring 42501 errors in production.
    await client
        .from('conversation_participants')
        .update({'draft': text.isEmpty ? null : text})
        .eq('conversation_id', conversationId)
        .eq('user_id', me.id);
  }

  /// Load the saved draft for the current user in a conversation.
  static Future<String?> loadDraft(String conversationId) async {
    final me = currentUser;
    if (me == null) return null;
    final row = await client
        .from('conversation_participants')
        .select('draft')
        .eq('conversation_id', conversationId)
        .eq('user_id', me.id)
        .maybeSingle();
    return row?['draft'] as String?;
  }

  // Realtime typing broadcast on the conversation's private channel.
  // Send over the joined websocket (not HTTP) and pulse while the peer types.
  static const _typingEvent = 'typing';

  static String _typingTopic(String conversationId) => 'typing:$conversationId';
  static final Map<String, RealtimeChannel> _typingChannels = {};

  static Future<void> broadcastTyping(
      String conversationId, bool isTyping) async {
    final channel = _typingChannels[conversationId];
    if (channel == null) return;
    final payload = <String, dynamic>{
      'user_id': currentUser?.id,
      'is_typing': isTyping,
    };
    try {
      await channel.sendBroadcastMessage(event: _typingEvent, payload: payload);
    } catch (_) {
      try {
        await channel.httpSend(event: _typingEvent, payload: payload);
      } catch (_) {}
    }
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
    channel.onBroadcast(
      event: _typingEvent,
      callback: (payload) {
        final uid = payload['user_id'] as String?;
        final typing = payload['is_typing'] as bool? ?? false;
        if (uid != null) onTyping(uid, typing);
      },
    );
    channel.subscribe();
  }

  static void unsubscribeTyping(String conversationId) {
    final channel = _typingChannels.remove(conversationId);
    if (channel != null) client.removeChannel(channel);
  }

  // ===== Reactions (delegated) =====

  static Future<void> addReaction(String messageId, String emoji) =>
      reactions.Reactions.add(messageId, emoji);

  static Future<void> removeReaction(String messageId, String emoji) =>
      reactions.Reactions.remove(messageId, emoji);

  static Future<List<Map<String, dynamic>>> getReactions(String messageId) =>
      reactions.Reactions.getAll(messageId);

  static Stream<List<Map<String, dynamic>>> watchReactions(String messageId) =>
      reactions.Reactions.watch(messageId);

  // ===== Reply-to (delegated) =====

  static String? validateMessageContent(String content) =>
      message_safety.MessageSafety.validateContent(content);

  static Future<Message> sendMessageWithReply({
    required String conversationId,
    required String content,
    String? replyToId,
    Duration? expiry,
    String? expectedSenderId,
  }) =>
      message_safety.MessageSafety.send(
        conversationId: conversationId,
        content: content,
        replyToId: replyToId,
        expiry: expiry,
        expectedSenderId: expectedSenderId,
      );

  static Future<Message?> getReplyPreview(String messageId) =>
      message_safety.MessageSafety.getReplyPreview(messageId);

  // ===== Read Receipts (delegated) =====

  static Future<bool> getReadReceiptsEnabled() =>
      read_receipts.ReadReceipts.isEnabled();

  static Future<void> setReadReceiptsEnabled(bool enabled) =>
      read_receipts.ReadReceipts.setEnabled(enabled);

  // ===== Block/Report (delegated) =====

  static Future<void> blockUser(String userId) =>
      block_report.BlockReport.block(userId);

  static Future<void> unblockUser(String userId) =>
      block_report.BlockReport.unblock(userId);

  static Future<bool> isUserBlocked(String userId) =>
      block_report.BlockReport.isBlocked(userId);

  static Future<List<String>> getBlockedUserIds() =>
      block_report.BlockReport.blockedIds();

  static Future<void> reportUser({
    required String userId,
    required String reason,
    String? details,
  }) =>
      block_report.BlockReport.report(
        userId: userId,
        reason: reason,
        details: details,
      );

  // ===== Conversation Peer Lookup =====

  /// Look up the peer user ID for a 1:1 conversation.
  static Future<String?> getPeerUserId(String conversationId) async {
    try {
      final me = currentUser?.id;
      if (me == null) return null;
      final res = await client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId)
          .neq('user_id', me);
      if ((res as List).isEmpty) return null;
      return res.first['user_id'] as String;
    } catch (_) {
      return null;
    }
  }

  /// Configure the Signal facade against the linked Supabase project.
  /// Public keys only are registered; private keys stay on this device.
  static Future<void> _configureSignal() async {
    final signal = SignalE2ee.instance;
    signal.fetchBundle ??= (userId) async {
      final devices = await client
          .from('signal_devices')
          .select('id,device_id,registration_id,identity_key,signed_prekey_id,'
                  'signed_prekey,signed_prekey_signature')
          .eq('user_id', userId)
          .isFilter('revoked_at', null)
          .order('device_id')
          .limit(1);
      if ((devices as List).isEmpty) return null;
      final device = devices.first;
      final deviceId = device['device_id'] as int;
      final deviceRowId = device['id'] as String;
      final prekeys = await client
          .from('signal_one_time_prekeys')
          .select('prekey_id,public_key')
          .eq('device_row_id', deviceRowId)
          .isFilter('used_at', null)
          .limit(1);
      // Atomic claim; the RPC authorises own devices and conversation peers.
      final claimed = await client.rpc('signal_claim_prekey', params: {
        'p_device_row_id': deviceRowId,
      });
      final claimRows = claimed as List?;
      final hasClaim = claimRows != null && claimRows.isNotEmpty;
      final prekeyRow = hasClaim
          ? claimRows.first as Map<String, dynamic>
          : (prekeys as List).isEmpty
              ? null
              : prekeys.first;
      // Kyber public material is stored alongside the signed prekey record.
      final kyber = await client
          .from('signal_kyber_prekeys')
          .select('prekey_id,public_key,signature')
          .eq('device_row_id', deviceRowId)
          .isFilter('used_at', null)
          .limit(1);
      if ((kyber as List).isEmpty) return null;
      final kyberRow = kyber.first;
      return SignalPublicBundle(
        userId: userId,
        deviceId: deviceId,
        registrationId: device['registration_id'] as int,
        identityKey: _decodeBytes(device['identity_key'] as String),
        signedPreKeyId: device['signed_prekey_id'] as int,
        signedPreKey: _decodeBytes(device['signed_prekey'] as String),
        signedPreKeySignature:
            _decodeBytes(device['signed_prekey_signature'] as String),
        preKeyId: prekeyRow?['prekey_id'] as int?,
        preKey: prekeyRow == null
            ? null
            : _decodeBytes(prekeyRow['public_key'] as String),
        kyberPreKeyId: kyberRow['prekey_id'] as int,
        kyberPreKey: _decodeBytes(kyberRow['public_key'] as String),
        kyberPreKeySignature: _decodeBytes(kyberRow['signature'] as String),
      );
    };

    signal.registerBundle ??= (
      deviceId,
      registrationId,
      identityKey,
      signedPreKeyId,
      signedPreKey,
      signedPreKeySignature,
      oneTimePreKeys,
      kyberPreKeyId,
      kyberPreKey,
      kyberPreKeySignature,
    ) async {
      final uid = currentUser?.id;
      if (uid == null) {
        throw const E2eeException(E2eeFailure.encryptionUnavailable);
      }
      final rows = await client
          .from('signal_devices')
          .upsert({
            'user_id': uid,
            'device_id': deviceId,
            'identity_key': _encodeBytes(identityKey),
            'registration_id': registrationId,
            'signed_prekey_id': signedPreKeyId,
            'signed_prekey': _encodeBytes(signedPreKey),
            'signed_prekey_signature': _encodeBytes(signedPreKeySignature),
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id,device_id')
          .select('id')
          .single();
      final rowId = rows['id'] as String;
      await client
          .from('signal_one_time_prekeys')
          .upsert([
            for (final entry in oneTimePreKeys)
              {
                'device_row_id': rowId,
                'prekey_id': entry.$1,
                'public_key': _encodeBytes(entry.$2),
                'used_at': null,
              }
          ], onConflict: 'device_row_id,prekey_id');
      await client.from('signal_kyber_prekeys').upsert({
        'device_row_id': rowId,
        'prekey_id': kyberPreKeyId,
        'public_key': _encodeBytes(kyberPreKey),
        'signature': _encodeBytes(kyberPreKeySignature),
        'used_at': null,
      }, onConflict: 'device_row_id,prekey_id');
    };
  }

  static String _encodeBytes(List<int> bytes) => base64Encode(bytes);
  static Uint8List _decodeBytes(String value) => Uint8List.fromList(base64Decode(value));

  /// Encrypts for one peer. Never returns plaintext on failure.
  static Future<String> encryptForConversation(
    String conversationId,
    String plaintext,
  ) async {
    final peer = await getPeerUserId(conversationId);
    if (peer == null) {
      throw const E2eeException(E2eeFailure.peerBundleUnavailable);
    }
    await _configureSignal();
    await SignalE2ee.instance.init();
    return SignalE2ee.instance.encrypt(peer, utf8.encode(plaintext));
  }

  /// Returns display text for a stored message. Legacy plaintext is returned
  /// unchanged and is NOT labelled encrypted. A `sig1:` envelope that fails
  /// decryption becomes an explicit error state, never plaintext.
  static String decryptMessageContent(
    String conversationId,
    String content,
    String? key,
  ) {
    if (!SignalE2ee.instance.isSecureEnvelope(content)) return content;
    // Decryption is asynchronous; watchMessages resolves it before mapping.
    return '[Encrypted message]';
  }

  /// Decrypts an envelope for display. Throws [E2eeException] on failure.
  static Future<String> decryptForDisplay(
    String senderUserId,
    String content,
  ) async {
    if (!SignalE2ee.instance.isSecureEnvelope(content)) return content;
    await _configureSignal();
    await SignalE2ee.instance.init();
    try {
      final bytes = await SignalE2ee.instance.decrypt(senderUserId, content);
      return utf8.decode(bytes);
    } on E2eeException catch (error) {
      return switch (error.reason) {
        E2eeFailure.identityChanged => '[Security warning: contact identity changed]',
        E2eeFailure.malformedEnvelope => '[Encrypted message: invalid format]',
        _ => '[Encrypted message: could not decrypt]',
      };
    }
  }

  /// Kept for API compatibility. Signal derives per-message keys; there is no
  /// reusable conversation key and no deterministic derivation.
  static Future<String?> getConversationKey(String conversationId) async => null;

  /// Safety number for out-of-band verification of the peer's Signal identity.
  static Future<String> safetyNumberForConversation(String conversationId) async {
    final peer = await getPeerUserId(conversationId);
    if (peer == null) {
      throw const E2eeException(E2eeFailure.peerBundleUnavailable);
    }
    await _configureSignal();
    await SignalE2ee.instance.init();
    return SignalE2ee.instance.safetyNumber(peer);
  }

  static Future<bool> isPeerVerifiedInConversation(
    String conversationId,
    String fingerprint,
  ) async {
    final peer = await getPeerUserId(conversationId);
    if (peer == null) return false;
    return SignalE2ee.instance.isPeerVerified(peer, fingerprint);
  }

  static Future<void> verifyPeerInConversation(
    String conversationId,
    String fingerprint,
  ) async {
    final peer = await getPeerUserId(conversationId);
    if (peer == null) {
      throw const E2eeException(E2eeFailure.peerBundleUnavailable);
    }
    await SignalE2ee.instance.verifyPeer(peer, fingerprint);
  }

  /// Notifier for chat background changes.
  /// Listen to this to refresh the chat background when settings change.
  static final chatBackgroundChanged = ValueNotifier<int>(0);

  /// Call this after updating the chat background to notify listeners.
  static void notifyChatBackgroundChanged() {
    chatBackgroundChanged.value++;
  }
}
