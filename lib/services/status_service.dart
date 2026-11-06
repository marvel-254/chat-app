import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';

class StatusService {
  static final client = Supabase.instance.client;

  static Future<void> createStatus({
    String? content,
    String? mediaPath,
    String? mood,
    String privacy = 'contacts',
  }) async {
    await client.from('statuses').insert({
      'user_id': client.auth.currentUser!.id,
      if (content != null && content.trim().isNotEmpty)
        'content': content.trim(),
      if (mediaPath != null) 'media_path': mediaPath,
      if (mood != null && mood.trim().isNotEmpty) 'mood': mood.trim(),
      'privacy': privacy,
      'created_at': DateTime.now().toIso8601String(),
      'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    });
  }

  static Future<void> deleteStatus(String statusId) async {
    await client.from('statuses').delete().eq('id', statusId);
  }

  static Stream<List<StatusPost>> watchStatuses() {
    return client
        .from('statuses')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          final now = DateTime.now();
          final activeRows = rows.where((r) {
            final exp = DateTime.tryParse(r['expires_at'] as String? ?? '\');
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
}
