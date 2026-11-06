class Profile {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String chatBackground;
  final String? chatBackgroundImagePath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? about;
  final String photoVisibility;
  final String statusVisibility;
  final String aboutVisibility;
  final DateTime? lastSeenAt;
  final bool readReceiptsEnabled;
  final Duration? defaultMessageExpiry;

  Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.chatBackground = 'default',
    this.chatBackgroundImagePath,
    required this.createdAt,
    required this.updatedAt,
    this.about,
    this.photoVisibility = 'everyone',
    this.statusVisibility = 'everyone',
    this.aboutVisibility = 'everyone',
    this.lastSeenAt,
    this.readReceiptsEnabled = true,
    this.defaultMessageExpiry,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        chatBackground: json['chat_background'] as String? ?? 'default',
        chatBackgroundImagePath: json['chat_background_image_path'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        about: json['about'] as String?,
        photoVisibility: json['photo_visibility'] as String? ?? 'everyone',
        statusVisibility: json['status_visibility'] as String? ?? 'everyone',
        aboutVisibility: json['about_visibility'] as String? ?? 'everyone',
        lastSeenAt: json['last_seen_at'] == null
            ? null
            : DateTime.parse(json['last_seen_at'] as String),
        readReceiptsEnabled: json['read_receipts_enabled'] as bool? ?? true,
        defaultMessageExpiry: parseInterval(json['default_message_expiry']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'chat_background': chatBackground,
        'chat_background_image_path': chatBackgroundImagePath,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Display label for this profile (display name, else username).
  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final user = username.trim();
    return user.isNotEmpty ? user : 'User';
  }

  /// First character used for the avatar, uppercased.
  String get peerInitial {
    final name = label;
    return name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  }
}

class Conversation {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Message>? messages;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? peerId;
  final String? peerUsername;
  final String? peerDisplayName;
  final String? peerAvatarUrl;
  final int unreadCount;
  final bool isLocked;

  Conversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.messages,
    this.lastMessage,
    this.lastMessageAt,
    this.peerId,
    this.peerUsername,
    this.peerDisplayName,
    this.peerAvatarUrl,
    this.unreadCount = 0,
    this.isLocked = false,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        messages: (json['messages'] as List?)
            ?.map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(),
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] == null
            ? null
            : DateTime.parse(json['last_message_at'] as String),
        peerUsername: json['peer_username'] as String?,
        peerDisplayName: json['peer_display_name'] as String?,
        peerAvatarUrl: json['peer_avatar_url'] as String?,
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
        isLocked: (json['is_locked'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// The display name to show for the other participant of this DM.
  String get peerLabel {
    final name = peerDisplayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final user = peerUsername?.trim();
    if (user != null && user.isNotEmpty) return user;
    return 'Chat';
  }

  /// First character used for the avatar, uppercased.
  String get peerInitial {
    final name = peerLabel;
    return name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  }
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? expiresAt;
  final DateTime? pinnedAt;
  final DateTime? editedAt;
  final String? originalContent;
  final bool readByPeer;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.readAt,
    this.expiresAt,
    this.pinnedAt,
    this.editedAt,
    this.originalContent,
    this.readByPeer = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] != null
            ? DateTime.parse(json['read_at'] as String)
            : null,
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String),
        pinnedAt: json['pinned_at'] == null
            ? null
            : DateTime.parse(json['pinned_at'] as String),
        editedAt: json['edited_at'] == null
            ? null
            : DateTime.parse(json['edited_at'] as String),
        originalContent: json['original_content'] as String?,
        readByPeer: (json['message_reads'] as List?)?.isNotEmpty ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'read_at': readAt?.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'pinned_at': pinnedAt?.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
        'original_content': originalContent,
      };
}

Duration? parseInterval(dynamic raw) {
  if (raw == null) return null;
  final str = raw.toString().trim();
  if (str.isEmpty ||
      str == '00:00:00' ||
      str == '0' ||
      str == '0 seconds' ||
      str == '00:00:00.000000') {
    return null;
  }
  final daysMatch = RegExp(r'(\d+(?:\.\d+)?)\s+days?').firstMatch(str);
  if (daysMatch != null) {
    final secs = (double.parse(daysMatch.group(1)!) * 86400).round();
    return secs == 0 ? null : Duration(seconds: secs);
  }
  final hoursMatch = RegExp(r'(\d+(?:\.\d+)?)\s+hours?').firstMatch(str);
  if (hoursMatch != null) {
    final secs = (double.parse(hoursMatch.group(1)!) * 3600).round();
    return secs == 0 ? null : Duration(seconds: secs);
  }
  final secsMatch = RegExp(r'(\d+)\s+secs?|\b(\d+)\s+seconds?').firstMatch(str);
  if (secsMatch != null) {
    final s = int.tryParse(secsMatch.group(1) ?? secsMatch.group(2) ?? '') ?? 0;
    return s == 0 ? null : Duration(seconds: s);
  }
  final parts = str.split(':');
  if (parts.length == 3) {
    final hours = int.tryParse(parts[0]) ?? 0;
    final mins = int.tryParse(parts[1]) ?? 0;
    final secs = double.tryParse(parts[2]) ?? 0.0;
    final dur = Duration(hours: hours, minutes: mins, seconds: secs.floor());
    return dur == Duration.zero ? null : dur;
  }
  return null;
}

class StatusPost {
  final String id;
  final String userId;
  final String? content;
  final String? mediaPath;
  final String? mood;
  final String privacy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? userUsername;
  final String? userDisplayName;
  final String? userAvatarUrl;

  StatusPost({
    required this.id,
    required this.userId,
    this.content,
    this.mediaPath,
    this.mood,
    this.privacy = 'contacts',
    required this.createdAt,
    required this.expiresAt,
    this.userUsername,
    this.userDisplayName,
    this.userAvatarUrl,
  });

  factory StatusPost.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    return StatusPost(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String?,
      mediaPath: json['media_path'] as String?,
      mood: json['mood'] as String?,
      privacy: json['privacy'] as String? ?? 'contacts',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      userUsername: profile?['username'] as String?,
      userDisplayName: profile?['display_name'] as String?,
      userAvatarUrl: profile?['avatar_url'] as String?,
    );
  }
}
