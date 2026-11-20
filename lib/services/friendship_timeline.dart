import 'dart:typed_data';

import '../models/friendship_timeline.dart';
import 'supabase.dart';

/// Friendship Timeline (#66): the private timeline between two friends.
///
/// Reads go through `friendship_timeline_for_peer`, a SECURITY DEFINER
/// function that resolves the 1:1 conversation between the caller and the
/// peer, then unions important dates, shared photos, pinned moments, and the
/// first message into one ordered list. Photos are stored in the same
/// private R2 bucket as chat attachments, so downloads reuse
/// [Supa.attachmentUrl].
class FriendshipTimelineService {
  FriendshipTimelineService._();

  /// Load the timeline for the friendship with [peerId], newest first.
  ///
  /// Never throws for a single bad row; those are dropped by
  /// [FriendshipTimelineEntry.tryParse].
  static Future<List<FriendshipTimelineEntry>> load(String peerId,
      {int limit = 100}) async {
    final me = Supa.currentUser?.id;
    if (me == null || me == peerId) return const [];

    final result = await Supa.client.rpc('friendship_timeline_for_peer',
        params: {'p_peer_id': peerId, 'p_limit': limit});
    if (result is! List) return const [];

    final entries = <FriendshipTimelineEntry>[];
    for (final row in result) {
      if (row is! Map) continue;
      final entry =
          FriendshipTimelineEntry.tryParse(Map<String, dynamic>.from(row));
      if (entry == null) continue;
      entries.add(entry);
    }
    return entries;
  }

  /// All photos shared with [peerId], oldest first (gallery order).
  static Future<List<FriendshipPhoto>> photos(String peerId) async {
    final rows = await _select('friendship_photos', peerId);
    return rows
        .map((row) => FriendshipPhoto.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// All important dates tracked with [peerId], soonest first.
  static Future<List<FriendshipDate>> dates(String peerId) async {
    final rows = await _select('friendship_dates', peerId);
    return rows
        .map((row) => FriendshipDate.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Upload [bytes] and pin it to the timeline.
  ///
  /// Goes through the existing attachment pipeline so the object lands in
  /// the private R2 bucket with the same authorization rules as a chat
  /// attachment.
  static Future<FriendshipPhoto> addPhoto(
    String peerId, {
    required Uint8List bytes,
    required String filename,
    String? caption,
    String? takenFromMessageId,
  }) async {
    final conversationId = await _conversationId(peerId);
    if (conversationId == null) {
      throw StateError('Open a chat with this friend first.');
    }
    if (bytes.isEmpty) {
      throw ArgumentError('Pick a photo to share.');
    }
    final uploaded = await Supa.uploadTimelineFile(
        conversationId, bytes, filename, _imageMime(filename));
    final row = await Supa.client
        .from('friendship_photos')
        .insert({
          'conversation_id': conversationId,
          'object_path': uploaded['path'] as String,
          if (caption != null && caption.trim().isNotEmpty)
            'caption': caption.trim(),
          if (takenFromMessageId != null)
            'taken_from_message_id': takenFromMessageId,
        })
        .select()
        .single();
    return FriendshipPhoto.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Add an important date to the timeline.
  static Future<FriendshipDate> addDate(
    String peerId, {
    required String title,
    required DateTime occursOn,
    bool remindAnnually = true,
  }) async {
    final conversationId = await _conversationId(peerId);
    if (conversationId == null) {
      throw StateError('Open a chat with this friend first.');
    }
    final row = await Supa.client
        .from('friendship_dates')
        .insert({
          'conversation_id': conversationId,
          'title': title.trim(),
          'occurs_on': _dateOnly(occursOn),
          'remind_annually': remindAnnually,
        })
        .select()
        .single();
    return FriendshipDate.fromJson(Map<String, dynamic>.from(row as Map));
  }

  /// Remove a photo the caller added. The DB row is deleted first so a
  /// storage failure can never leave an orphaned row; the stored object is
  /// then removed on a best-effort basis.
  static Future<void> removePhoto(FriendshipPhoto photo) async {
    await Supa.client.from('friendship_photos').delete().eq('id', photo.id);
    await Supa.deleteAttachment(photo.objectPath);
  }

  /// Remove an important date the caller added.
  static Future<void> removeDate(FriendshipDate date) async {
    await Supa.client.from('friendship_dates').delete().eq('id', date.id);
  }

  /// Rows from [table] that belong to the friendship with [peerId], filtered
  /// down to the caller's 1:1 conversation.
  static Future<List<Map<String, dynamic>>> _select(
      String table, String peerId) async {
    final me = Supa.currentUser?.id;
    if (me == null || me == peerId) return const [];
    final shared = await Supa.client
        .rpc('shares_conversation', params: {'a': me, 'b': peerId});
    if (shared != true) return const [];
    final rows = await Supa.client
        .from(table)
        .select()
        .eq('owner_id', me)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  /// Resolve the 1:1 conversation id shared with [peerId], or null.
  static Future<String?> _conversationId(String peerId) async {
    final me = Supa.currentUser?.id;
    if (me == null || me == peerId) return null;
    try {
      final shared = await Supa.client
          .rpc('shares_conversation', params: {'a': me, 'b': peerId});
      if (shared != true) return null;
      final rows = await Supa.client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', me);
      final mine = (rows as List)
          .map((row) => row['conversation_id'] as String)
          .toList();
      if (mine.isEmpty) return null;
      final theirs = await Supa.client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', peerId)
          .inFilter('conversation_id', mine)
          .limit(1);
      if ((theirs as List).isEmpty) return null;
      return theirs.first['conversation_id'] as String;
    } catch (_) {
      return null;
    }
  }

  static String _dateOnly(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _imageMime(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }
}
