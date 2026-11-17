import 'dart:developer' as dev;

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/circle.dart';

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

  /// Watch circles for the current user via periodic polling.
  static Stream<List<Circle>> watchMyCircles() async* {
    yield await getAllCircles();
    yield* Stream.periodic(const Duration(seconds: 60))
        .asyncMap((_) => getAllCircles());
  }

  static Circle _mapCircleRow(Map<String, dynamic> row) {
    return Circle(
      id: row['circle_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      avatarPath: row['avatar_path'] as String?,
      isPrivate: row['is_private'] as bool? ?? false,
      creatorId: row['creator_id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
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
      userId: row['user_id'] as String,
      displayName: row['display_name'] as String? ?? '',
      username: row['username'] as String,
      avatarUrl: row['avatar_url'] as String?,
      joinedAt: DateTime.parse(row['joined_at'] as String),
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
}
