/// Call history domain model shared by the UI, service and tests.
///
/// Statuses are intentionally explicit: a cancelled outgoing call is never a
/// missed call, and a failed call is never reported as completed.
class CallRecord {
  const CallRecord({
    required this.id,
    required this.callId,
    required this.conversationId,
    required this.peerUserId,
    required this.kind,
    required this.direction,
    required this.status,
    required this.startedAt,
    this.connectedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.failureReason,
  });

  static const String kindVoice = 'voice';
  static const String kindVideo = 'video';

  static const String directionIncoming = 'incoming';
  static const String directionOutgoing = 'outgoing';

  static const String statusCompleted = 'completed';
  static const String statusMissed = 'missed';
  static const String statusRejected = 'rejected';
  static const String statusCancelled = 'cancelled';
  static const String statusUnanswered = 'unanswered';
  static const String statusFailed = 'failed';

  final String id;
  final String callId;
  final String conversationId;
  final String peerUserId;
  final String kind;
  final String direction;
  final String status;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String? failureReason;

  bool get isVideo => kind == kindVideo;
  bool get isIncoming => direction == directionIncoming;
  bool get isOutgoing => direction == directionOutgoing;
  bool get isMissed => status == statusMissed;
  bool get isFailed => status == statusFailed;
  bool get isRejected => status == statusRejected;
  bool get isCancelled => status == statusCancelled;
  bool get isCompleted => status == statusCompleted;

  /// Only completed calls may show a duration. Reconnections do not reset it.
  bool get hasDuration => isCompleted && connectedAt != null;

  /// Stable idempotency key used for deduplication and notification delivery.
  String get dedupeKey => '$callId:$peerUserId';

  static CallRecord fromJson(Map<String, dynamic> json) => CallRecord(
        id: json['id'] as String,
        callId: json['call_id'] as String,
        conversationId: json['conversation_id'] as String,
        peerUserId: json['peer_user_id'] as String,
        kind: json['kind'] as String? ?? kindVoice,
        direction: json['direction'] as String? ?? directionOutgoing,
        status: json['status'] as String? ?? statusFailed,
        startedAt: DateTime.parse(json['started_at'] as String),
        connectedAt: json['connected_at'] == null
            ? null
            : DateTime.parse(json['connected_at'] as String),
        endedAt: json['ended_at'] == null
            ? null
            : DateTime.parse(json['ended_at'] as String),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        failureReason: json['failure_reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'call_id': callId,
        'conversation_id': conversationId,
        'peer_user_id': peerUserId,
        'kind': kind,
        'direction': direction,
        'status': status,
        'started_at': startedAt.toUtc().toIso8601String(),
        'connected_at': connectedAt?.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'failure_reason': failureReason,
      };

  CallRecord copyWith({
    String? status,
    DateTime? connectedAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? failureReason,
  }) =>
      CallRecord(
        id: id,
        callId: callId,
        conversationId: conversationId,
        peerUserId: peerUserId,
        kind: kind,
        direction: direction,
        status: status ?? this.status,
        startedAt: startedAt,
        connectedAt: connectedAt ?? this.connectedAt,
        endedAt: endedAt ?? this.endedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        failureReason: failureReason ?? this.failureReason,
      );
}

/// Human-readable duration, e.g. "2 min 34 sec". Sub-second calls read
/// "Under a second" instead of displaying a misleading zero.
String formatCallDuration(int seconds) {
  if (seconds <= 0) return 'Under a second';
  if (seconds < 60) return '$seconds sec';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (remainder == 0) return '$minutes min';
  return '$minutes min $remainder sec';
}

/// Determines the final call status from the local perspective.
///
/// [localHangup] is true when this user ended the call. [reason] carries
/// timeout/network failure information from the call state machine.
String resolveCallStatus({
  required bool outgoing,
  required bool answered,
  required bool localHangup,
  required bool peerHangup,
  String? reason,
}) {
  if (reason == 'networkFailure' || reason == 'permissionDenied') {
    return CallRecord.statusFailed;
  }
  if (answered) return CallRecord.statusCompleted;
  if (localHangup) {
    return outgoing
        ? CallRecord.statusCancelled
        : CallRecord.statusRejected;
  }
  if (peerHangup) {
    return outgoing
        ? CallRecord.statusUnanswered
        : CallRecord.statusMissed;
  }
  return outgoing ? CallRecord.statusUnanswered : CallRecord.statusMissed;
}

/// Keeps the first authoritative row for a call id.
///
/// Late or duplicated signalling events cannot overwrite a final state.
List<CallRecord> dedupeCallRecords(Iterable<CallRecord> records) {
  final byKey = <String, CallRecord>{};
  for (final record in records) {
    final existing = byKey[record.dedupeKey];
    if (existing == null || _statusRank(record.status) > _statusRank(existing.status)) {
      byKey[record.dedupeKey] = record;
    }
  }
  final ordered = byKey.values.toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return ordered;
}

int _statusRank(String status) => switch (status) {
      CallRecord.statusCompleted => 5,
      CallRecord.statusMissed ||
      CallRecord.statusRejected ||
      CallRecord.statusCancelled ||
      CallRecord.statusUnanswered =>
        4,
      _ => 1,
    };
