import 'package:uuid/uuid.dart';

/// One entry on a friendship timeline: an important date, a shared photo,
/// or a memorable (pinned) moment.
///
/// The timeline is assembled server-side by
/// `friendship_timeline_for_peer` (migration 20261118120000), so this model
/// is a plain, defensive reader over that result. Rows that do not parse are
/// skipped by [FriendshipTimelineEntry.tryParse] instead of throwing, which
/// keeps one malformed row from blanking the whole timeline.
class FriendshipTimelineEntry {
  const FriendshipTimelineEntry({
    required this.id,
    required this.kind,
    required this.conversationId,
    required this.createdAt,
    this.photoPath,
    this.photoCaption,
    this.photoMessageId,
    this.dateTitle,
    this.occursOn,
    this.remindAnnually,
    this.momentMessageId,
    this.momentPreview,
    this.momentPinnedAt,
    this.momentSenderId,
  });

  /// Kinds returned by the RPC, in display order of precedence.
  static const kindDate = 'date';
  static const kindPhoto = 'photo';
  static const kindMoment = 'moment';
  static const kindFirstMessage = 'first_message';

  final String id;
  final String kind;
  final String conversationId;
  final DateTime createdAt;

  // date
  final String? dateTitle;
  final DateTime? occursOn;
  final bool? remindAnnually;

  // photo
  final String? photoPath;
  final String? photoCaption;
  final String? photoMessageId;

  // moment / first message
  final String? momentMessageId;
  final String? momentPreview;
  final DateTime? momentPinnedAt;
  final String? momentSenderId;

  bool get isDate => kind == kindDate;
  bool get isPhoto => kind == kindPhoto;
  bool get isMoment => kind == kindMoment;
  bool get isFirstMessage => kind == kindFirstMessage;

  /// Short label shown under the icon in the timeline rail.
  String get railLabel => switch (kind) {
        kindDate => 'Important date',
        kindPhoto => 'Shared photo',
        kindMoment => 'Pinned moment',
        kindFirstMessage => 'First message',
        _ => 'Memory',
      };

  factory FriendshipTimelineEntry.fromJson(Map<String, dynamic> json) {
    return FriendshipTimelineEntry(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      photoPath: json['photo_path'] as String?,
      photoCaption: json['photo_caption'] as String?,
      photoMessageId: json['photo_message_id'] as String?,
      dateTitle: json['date_title'] as String?,
      occursOn: json['occurs_on'] == null
          ? null
          : DateTime.parse(json['occurs_on'] as String),
      remindAnnually: json['remind_annually'] as bool?,
      momentMessageId: json['moment_message_id'] as String?,
      momentPreview: json['moment_preview'] as String?,
      momentPinnedAt: json['moment_pinned_at'] == null
          ? null
          : DateTime.parse(json['moment_pinned_at'] as String),
      momentSenderId: json['moment_sender_id'] as String?,
    );
  }

  /// Like [fromJson], but returns null instead of throwing on a bad row.
  static FriendshipTimelineEntry? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final createdAt = json['created_at'];
    if (id is! String || id.isEmpty) return null;
    if (createdAt is! String) return null;
    final parsedAt = DateTime.tryParse(createdAt);
    if (parsedAt == null) return null;
    try {
      return FriendshipTimelineEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'conversation_id': conversationId,
        'created_at': createdAt.toIso8601String(),
        'photo_path': photoPath,
        'photo_caption': photoCaption,
        'photo_message_id': photoMessageId,
        'date_title': dateTitle,
        'occurs_on': occursOn?.toIso8601String(),
        'remind_annually': remindAnnually,
        'moment_message_id': momentMessageId,
        'moment_preview': momentPreview,
        'moment_pinned_at': momentPinnedAt?.toIso8601String(),
        'moment_sender_id': momentSenderId,
      };
}

/// An important date two friends track on their timeline.
class FriendshipDate {
  const FriendshipDate({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.occursOn,
    this.remindAnnually = true,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String title;
  final DateTime occursOn;
  final bool remindAnnually;
  final DateTime createdAt;

  factory FriendshipDate.fromJson(Map<String, dynamic> json) => FriendshipDate(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        occursOn: DateTime.tryParse(json['occurs_on'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        remindAnnually: json['remind_annually'] as bool? ?? true,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'title': title,
        'occurs_on': occursOn.toIso8601String(),
        'remind_annually': remindAnnually,
        'created_at': createdAt.toIso8601String(),
      };

  /// "12 Dec" — the day shown on the timeline rail.
  String get dayLabel {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${occursOn.day} ${months[occursOn.month - 1]}';
  }
}

/// A photo two friends pinned to their timeline.
///
/// The bytes live in the private R2 bucket behind the storage Worker, so the
/// app resolves a short-lived URL through [Supa.attachmentUrl] (same path as
/// chat attachments) rather than a public link.
class FriendshipPhoto {
  const FriendshipPhoto({
    required this.id,
    required this.conversationId,
    required this.objectPath,
    this.caption,
    this.takenFromMessageId,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String objectPath;
  final String? caption;
  final String? takenFromMessageId;
  final DateTime createdAt;

  factory FriendshipPhoto.fromJson(Map<String, dynamic> json) =>
      FriendshipPhoto(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String? ?? '',
        objectPath: json['object_path'] as String? ?? '',
        caption: json['caption'] as String?,
        takenFromMessageId: json['taken_from_message_id'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'object_path': objectPath,
        'caption': caption,
        'taken_from_message_id': takenFromMessageId,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Generates ids for optimistic local rows before the server confirms them.
String newLocalId() => const Uuid().v4();
