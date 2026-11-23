import 'dart:async';
import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/circle.dart';
import 'circle_realtime.dart';

class Circles {
  static final client = Supabase.instance.client;

  /// Create a new circle
  static Future<String> create({
    required String name,
    String? description,
    bool isPrivate = false,
    String? avatarPath,
  }) async {
    final dynamic result = await client.rpc('create_circle', params: {
      'p_name': name,
      'p_description': description,
      'p_is_private': isPrivate,
      'p_avatar_path': avatarPath,
    });
    return result as String;
  }

  /// Join a circle
  static Future<void> join(String circleId) async {
    await client.rpc('join_circle', params: {'p_circle_id': circleId});
  }

  /// Leave a circle
  static Future<void> leave(String circleId) async {
    await client.rpc('leave_circle', params: {'p_circle_id': circleId});
  }

  /// Get all circles for the current user (including groups)
  static Future<List<Circle>> getAllCircles() async {
    try {
      final result = await client.rpc('get_user_circles', params: {});
      if (result is List) {
        dev.log('getAllCircles: ${result.length} circles found');
        return result
            .map((row) => _mapCircleRow(row as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      dev.log('getAllCircles failed: $e', error: e);
      rethrow;
    }
  }

  /// Shared Realtime + polling stream. Realtime is primary; the 60s poll stays
  /// as a fallback when the publication or socket is unavailable.
  static Stream<T> _watch<T>(
    String topic,
    Future<T> Function() fetch, {
    required List<String> tables,
    bool emitInitial = true,
  }) {
    final controller = StreamController<T>.broadcast();
    final debouncer = CircleRealtime();
    StreamSubscription<void>? poll;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      if (controller.isClosed) return;
      try {
        final value = await fetch();
        if (!controller.isClosed) controller.add(value);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    void schedule() => debouncer.schedule(() => unawaited(refresh()));

    controller.onListen = () {
      if (emitInitial) unawaited(refresh());
      final uid = client.auth.currentUser?.id;
      if (uid != null) {
        try {
          RealtimeChannel built = client.channel(topic);
          for (final table in tables) {
            built = built.onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: table,
              callback: (_) => schedule(),
            );
          }
          channel = built..subscribe();
        } catch (e) {
          dev.log('Circle realtime setup failed: $e', error: e);
        }
      }
      poll = Stream<void>.periodic(const Duration(seconds: 60))
          .listen((_) => unawaited(refresh()));
    };

    controller.onCancel = () {
      debouncer.cancel();
      poll?.cancel();
      final active = channel;
      channel = null;
      if (active != null) unawaited(client.removeChannel(active));
    };
    return controller.stream;
  }

  /// Circles for the current user, refreshed on any circle or membership change.
  static Stream<List<Circle>> watchMyCircles() => _watch<List<Circle>>(
        'bro-circles:${client.auth.currentUser?.id ?? 'anon'}',
        getAllCircles,
        tables: const ['circles', 'circle_participants', 'circle_invites'],
      );

  /// Invitations addressed to the current user.
  static Stream<List<CircleInvite>> watchPendingInvites() =>
      _watch<List<CircleInvite>>(
        'bro-circle-invites:${client.auth.currentUser?.id ?? 'anon'}',
        pendingInvites,
        tables: const ['circle_invites'],
      );

  /// Emits whenever anything affecting one circle changes. The value is not
  /// used; subscribers refetch their own detail view.
  static Stream<void> watchCircleChanges(String circleId) => _watch<int>(
        'bro-circle-detail:$circleId',
        () async => 0,
        tables: const ['circles', 'circle_participants', 'circle_invites'],
        emitInitial: false,
      );

  static Circle _mapCircleRow(Map<String, dynamic> row) {
    return Circle(
      id: row['circle_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      description: row['description'] as String?,
      avatarPath: row['avatar_path'] as String?,
      isPrivate: row['is_private'] as bool? ?? false,
      creatorId: row['creator_id'] as String? ?? '',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
      memberCount: row['member_count'] as int? ?? 0,
      isMember: row['is_member'] as bool? ?? false,
    );
  }

  /// Get all members of a circle
  static Future<List<CircleMember>> getCircleMembers(String circleId) async {
    final result = await client
        .rpc('get_circle_members', params: {'p_circle_id': circleId});
    if (result is List) {
      return result
          .map((row) => _mapCircleMemberRow(row as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  static CircleMember _mapCircleMemberRow(Map<String, dynamic> row) {
    return CircleMember(
      userId: row['user_id'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      username: row['username'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
      joinedAt: DateTime.tryParse(row['joined_at'] as String? ?? '') ?? DateTime.now(),
      isAdmin: row['is_admin'] as bool? ?? false,
    );
  }

  /// Delete a circle (only creator)
  static Future<void> deleteCircle(String circleId) async {
    await client.from('circles').delete().eq('id', circleId);
  }

  /// Update circle details
  static Future<void> updateCircle(
    String circleId, {
    String? name,
    String? description,
    String? avatarPath,
    bool? isPrivate,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (avatarPath != null) updates['avatar_path'] = avatarPath;
    if (isPrivate != null) updates['is_private'] = isPrivate;
    updates['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId == null) return;

    await client
        .from('circles')
        .update(updates)
        .eq('id', circleId)
        .eq('creator_id', currentUserId);
  }

  /// Check if current user is an admin of a circle
  static Future<bool> isAdmin(String circleId) async {
    final me = client.auth.currentUser?.id;
    if (me == null) return false;

    final res = await client
        .from('circle_participants')
        .select('is_admin')
        .eq('circle_id', circleId)
        .eq('user_id', me)
        .maybeSingle();
    return res?['is_admin'] == true;
  }

  /// Get conversation ID associated with this circle
  static Future<String?> getConversationId(String circleId) async {
    final res = await client
        .rpc('get_conversation_for_circle', params: {'p_circle_id': circleId});
    return res as String?;
  }

  /// Link a conversation to a circle
  static Future<String> linkConversation(
      String conversationId, String circleId) async {
    final res = await client.rpc('link_circle_to_conversation', params: {
      'p_conversation_id': conversationId,
      'p_circle_id': circleId,
    });
    return res as String;
  }

  /// Unlink a circle from its conversation
  static Future<void> unlinkConversation(String circleId) async {
    final convId = await getConversationId(circleId);
    if (convId != null) {
      await client.rpc('unlink_circle_from_conversation',
          params: {'p_conversation_id': convId});
    }
  }

  /// Read a single circle without fetching every visible circle first.
  static Future<Circle?> getCircle(String circleId) async {
    final result = await client.rpc('get_circle', params: {'p_circle_id': circleId});
    if (result is! List || result.isEmpty) return null;
    return _mapCircleRow(result.first as Map<String, dynamic>);
  }

  /// Invite a user by id. Authorization is enforced by the RPC, not the client.
  static Future<String> invite(String circleId, String userId) async {
    final result = await client.rpc('invite_to_circle', params: {
      'p_circle_id': circleId,
      'p_user_id': userId,
    });
    return result as String;
  }

  /// Invitations addressed to the signed-in user.
  static Future<List<CircleInvite>> pendingInvites() async {
    final result = await client.rpc('circle_pending_invites');
    if (result is! List) return const [];
    return result
        .map((row) => CircleInvite.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Pending invitations for a circle, visible to its creator and admins.
  static Future<List<Map<String, dynamic>>> invitesForCircle(String circleId) async {
    final result = await client
        .rpc('circle_invites_for_circle', params: {'p_circle_id': circleId});
    if (result is! List) return const [];
    return result.cast<Map<String, dynamic>>();
  }

  static Future<void> acceptInvite(String inviteId) =>
      client.rpc('accept_circle_invite', params: {'p_invite_id': inviteId});

  static Future<void> declineInvite(String inviteId) =>
      client.rpc('decline_circle_invite', params: {'p_invite_id': inviteId});

  /// Admin-only removal. The creator cannot be removed from their own circle.
  static Future<void> removeMember(String circleId, String userId) =>
      client.rpc('remove_circle_member', params: {
        'p_circle_id': circleId,
        'p_user_id': userId,
      });
}
