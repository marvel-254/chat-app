class Profile {
  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
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
  final int unreadCount;

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
    this.unreadCount = 0,
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
        unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
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

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.readAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'read_at': readAt?.toIso8601String(),
      };
}