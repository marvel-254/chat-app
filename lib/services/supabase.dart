import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/profile.dart';
import '../models/profile_theme.dart';
import 'search_safety.dart';
import 'reactions.dart' as reactions;
import 'message_safety.dart' as message_safety;
import 'read_receipts.dart' as read_receipts;
import 'block_report.dart' as block_report;
import 'e2ee.dart' as e2ee;

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
        request.ilike('username', '$prefixTerm%').order('username').limit(limit),
      contains,
    ]);
    return rankPeopleSearchResults(
      results.expand((rows) => rows.map(Profile.fromJson)),
      term,
      limit: limit,
    );
  }

  // Friend Suggestions
  static Future<List<FriendSuggestion>> getFriendSuggestions(
      {int limit = 20, int offset = 0}) async {
    try {
      final res = await client.rpc('get_friend_suggestions', params: {
        'p_limit': limit,
        'p_offset': offset,
      });
      debugPrint('getFriendSuggestions -> ${(res as List).length} results');
      return (res as List)
          .map((e) => FriendSuggestion.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getFriendSuggestions failed: $e');
      rethrow;
    }
  }

  static Future<List<FriendSuggestion>> getFriendSuggestionsByCategory(
      String category, {int limit = 10}) async {
    try {
      final res = await client.rpc('get_friend_suggestions_by_category', params: {
        'p_category': category,
        'p_limit': limit,
      });
      debugPrint('getFriendSuggestionsByCategory("$category") -> ${(res as List).length} results');
      return (res as List)
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
      Duration? autoLockTimer}) async {
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

  static Future<void> updateProfileTheme(ProfileTheme theme) async {
    final updates = <String, dynamic>{
      ...theme.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await client.from('profiles').update(updates).eq('id', currentUser!.id);
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

      var profileQuery = client
          .from('visible_profiles')
          .select()
          .filter('id', 'in', ids) as dynamic;
      final term = sanitizeSearchTerm(search ?? '');
      if (term.isNotEmpty) {
        profileQuery = profileQuery
            .or('username.ilike.%$term%,display_name.ilike.%$term%');
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

      var profileQuery = client
          .from('visible_profiles')
          .select()
          .filter('id', 'in', ids) as dynamic;
      final term = sanitizeSearchTerm(search ?? '');
      if (term.isNotEmpty) {
        profileQuery = profileQuery
            .or('username.ilike.%$term%,display_name.ilike.%$term%');
      }
      final profs = await profileQuery;
      return (profs as List)
          .map((p) => Profile.fromJson(p as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

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
    // The canonical write target is `profiles` (itself). The UI reads
    // `visible_profiles` (a live view over `profiles` that re-implements the
    // privacy masking), so this row update is reflected in every chat list,
    // chat header, and settings view without any denormalised columns.
    final url = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    try {
      await client.from('profiles').update({
        'avatar_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
    } on PostgrestException catch (e) {
      // If RLS blocks the update, still return the URL so the UI can show it
      // The user will see the new avatar locally even if server sync fails
      if (e.code != '42501') rethrow;
    }
    // Force a refetch of the conversation list so the new avatar
    // (from profiles.avatar_url) is surfaced to all conversation views.
    triggerConversationRefresh();
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

  /// Download a GIF from a URL and upload it to storage as an attachment.
  static Future<Map<String, dynamic>> uploadAttachmentFromUrl(
      String conversationId, String url, String extension) async {
    final response = await http.get(Uri.parse(url));
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
            } catch (_) {}
          }

          // Fetch E2EE key for this conversation (cached after first call)
          final e2eeKey = await getConversationKey(conversationId);

          final now = DateTime.now();
          return rows
              .where((r) =>
                  !hiddenIds.contains(r['id'] as String) &&
                  (r['expires_at'] == null ||
                      DateTime.parse(r['expires_at'] as String).isAfter(now)))
              .map((r) {
            final id = r['id'] as String;
            final msg = Message.fromJson(r);
            // Decrypt the content if it was encrypted
            String content = msg.content;
            final decrypted =
                decryptMessageContent(conversationId, msg.content, e2eeKey);
            if (decrypted != null) {
              content = decrypted;
            }
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
          }).toList();
        });
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
    // Fetch current row to get conversation_id for re-encryption
    final current = await client
        .from('messages')
        .select('content,conversation_id')
        .eq('id', messageId)
        .single();
    final previousContent = current['content'] as String;
    final conversationId = current['conversation_id'] as String;
    // Re-encrypt the new content
    final encryptedContent =
        await encryptForConversation(conversationId, content);
    // Record edit history (store the encrypted content for consistency)
    await client.from('message_edit_history').insert({
      'message_id': messageId,
      'previous_content': previousContent,
      'new_content': encryptedContent,
    });
    // Update the message (trigger sets edited_at)
    await client
        .from('messages')
        .update({'content': encryptedContent}).eq('id', messageId);
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

  // ===== Drafts =====

  /// Save a draft for the current user in a conversation.
  static Future<void> saveDraft(String conversationId, String text) async {
    final me = currentUser;
    if (me == null) return;
    await client.from('conversation_participants').upsert({
      'conversation_id': conversationId,
      'user_id': me.id,
      'draft': text.isEmpty ? null : text,
    }, onConflict: 'conversation_id,user_id');
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
        .single();
    return row['draft'] as String?;
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

  // ===== E2EE Helpers =====

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

  /// Encrypt plaintext for a conversation, or return the original plaintext
  /// if encryption is not available (fallback for backward compatibility).
  static Future<String> encryptForConversation(
    String conversationId,
    String plaintext,
  ) async {
    try {
      final me = currentUser?.id;
      if (me == null) return plaintext;
      final peer = await getPeerUserId(conversationId);
      if (peer == null) return plaintext;
      final key = await e2ee.getOrDeriveKey(conversationId, me, peer);
      return e2ee.encrypt(key, plaintext);
    } catch (_) {
      return plaintext;
    }
  }

  /// Decrypt a message's content, falling back to the original if decryption
  /// fails (e.g. the message was sent before E2EE was enabled).
  static String? decryptMessageContent(
    String conversationId,
    String content,
    String? key,
  ) {
    if (key == null || key.isEmpty) return null;
    if (!e2ee.isEncrypted(content)) return null;
    return e2ee.decrypt(key, content);
  }

  /// Get or derive the E2EE key for a conversation.
  static Future<String?> getConversationKey(String conversationId) async {
    try {
      final me = currentUser?.id;
      if (me == null) return null;
      final peer = await getPeerUserId(conversationId);
      if (peer == null) return null;
      return await e2ee.getOrDeriveKey(conversationId, me, peer);
    } catch (_) {
      return null;
    }
  }

  /// Notifier for chat background changes.
  /// Listen to this to refresh the chat background when settings change.
  static final chatBackgroundChanged = ValueNotifier<int>(0);

  /// Call this after updating the chat background to notify listeners.
  static void notifyChatBackgroundChanged() {
    chatBackgroundChanged.value++;
  }
}
