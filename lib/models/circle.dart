class Circle {
  final String id;
  final String name;
  final String? description;
  final String? avatarPath;
  final bool isPrivate;
  final String creatorId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final bool isMember;

  const Circle({
    required this.id,
    required this.name,
    this.description,
    this.avatarPath,
    required this.isPrivate,
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    required this.isMember,
  });

  Circle copyWith({
    String? id,
    String? name,
    String? description,
    String? avatarPath,
    bool? isPrivate,
    String? creatorId,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? memberCount,
    bool? isMember,
  }) {
    return Circle(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      avatarPath: avatarPath ?? this.avatarPath,
      isPrivate: isPrivate ?? this.isPrivate,
      creatorId: creatorId ?? this.creatorId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      memberCount: memberCount ?? this.memberCount,
      isMember: isMember ?? this.isMember,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatar_path': avatarPath,
      'is_private': isPrivate,
      'creator_id': creatorId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'member_count': memberCount,
      'is_member': isMember,
    };
  }

  factory Circle.fromJson(Map<String, dynamic> json) {
    return Circle(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      avatarPath: json['avatar_path'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      creatorId: json['creator_id'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      memberCount: json['member_count'] as int? ?? 0,
      isMember: json['is_member'] as bool? ?? false,
    );
  }
}

class CircleMember {
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;
  final DateTime joinedAt;
  final bool isAdmin;

  const CircleMember({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
    required this.joinedAt,
    required this.isAdmin,
  });

  CircleMember copyWith({
    String? userId,
    String? displayName,
    String? username,
    String? avatarUrl,
    DateTime? joinedAt,
    bool? isAdmin,
  }) {
    return CircleMember(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinedAt: joinedAt ?? this.joinedAt,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'username': username,
      'avatar_url': avatarUrl,
      'joined_at': joinedAt.toIso8601String(),
      'is_admin': isAdmin,
    };
  }

  factory CircleMember.fromJson(Map<String, dynamic> json) {
    return CircleMember(
      userId: json['user_id'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? '') ?? DateTime.now(),
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }
}