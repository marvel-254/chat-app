import '../models/profile.dart';

/// One person's active statuses, oldest first for the viewer.
class StatusThread {
  StatusThread({required this.userId, required this.posts});

  final String userId;
  final List<StatusPost> posts;

  StatusPost get latest => posts.last;
  StatusPost get first => posts.first;
  int get count => posts.length;
}

/// Groups a flat status list into WhatsApp-style threads.
/// The current user's thread (if any) is always first; others are newest-latest first.
List<StatusThread> groupStatusFeed(List<StatusPost> posts, String myId) {
  final byUser = <String, List<StatusPost>>{};
  for (final post in posts) {
    byUser.putIfAbsent(post.userId, () => []).add(post);
  }
  for (final list in byUser.values) {
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  final mine = byUser.remove(myId);
  final others = byUser.values.toList()
    ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));

  return [
    if (mine != null && mine.isNotEmpty) StatusThread(userId: myId, posts: mine),
    ...others.map((list) => StatusThread(userId: list.first.userId, posts: list)),
  ];
}

String statusPrivacyLabel(String privacy) => switch (privacy) {
      'everyone' => 'Everyone',
      'followers' => 'Followers',
      _ => 'Contacts',
    };

String statusTimeAgo(DateTime dt, DateTime now) {
  final delta = now.difference(dt.toLocal());
  if (delta.inSeconds < 45) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

String statusTimeLeft(DateTime expiresAt, DateTime now) {
  final delta = expiresAt.toLocal().difference(now);
  if (delta.isNegative) return 'expired';
  if (delta.inMinutes < 60) return '${delta.inMinutes.clamp(1, 59)}m left';
  if (delta.inHours < 24) return '${delta.inHours}h left';
  return '${delta.inDays}d left';
}
