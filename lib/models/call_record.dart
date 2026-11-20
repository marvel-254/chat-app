enum CallStatus {
  ringing,
  accepted,
  connected,
  completed,
  missed,
  rejected,
  cancelled,
  busy,
  failed;

  bool get terminal => switch (this) {
        ringing || accepted || connected => false,
        _ => true,
      };
}

enum CallFilter { all, missed, incoming, outgoing }

class CallRecord {
  CallRecord(this.json)
      : id = json['id'] as String,
        conversationId = json['conversation_id'] as String,
        callerId = json['caller_id'] as String,
        calleeId = json['callee_id'] as String,
        video = json['video'] as bool,
        status = CallStatus.values.byName(json['status'] as String),
        startedAt = DateTime.parse(json['started_at'] as String),
        expiresAt = DateTime.parse(json['expires_at'] as String),
        connectedAt = DateTime.tryParse(json['connected_at'] as String? ?? ''),
        endedAt = DateTime.tryParse(json['ended_at'] as String? ?? '');

  final Map<String, dynamic> json;
  final String id, conversationId, callerId, calleeId;
  final bool video;
  final CallStatus status;
  final DateTime startedAt, expiresAt;
  final DateTime? connectedAt, endedAt;

  bool outgoing(String user) => callerId == user;
  String peerId(String user) => outgoing(user) ? calleeId : callerId;
  bool matches(CallFilter filter, String user) => switch (filter) {
        CallFilter.all => true,
        CallFilter.missed => !outgoing(user) && status == CallStatus.missed,
        CallFilter.incoming => !outgoing(user),
        CallFilter.outgoing => outgoing(user),
      };
  String outcome(String user) => switch (status) {
        CallStatus.ringing => 'Ringing',
        CallStatus.accepted => 'Connecting',
        CallStatus.connected => 'Connected',
        CallStatus.completed => 'Completed',
        CallStatus.missed => outgoing(user) ? 'Unanswered' : 'Missed',
        CallStatus.rejected => 'Declined',
        CallStatus.cancelled => 'Cancelled',
        CallStatus.busy => 'Busy',
        CallStatus.failed => 'Failed',
      };
  Duration? get duration {
    final start = connectedAt;
    final end = endedAt;
    if (start == null || end == null) return null;
    return end.isBefore(start) ? Duration.zero : end.difference(start);
  }

  static String formatDuration(Duration duration) => duration.inMinutes == 0
      ? '${duration.inSeconds} sec'
      : '${duration.inMinutes} min ${duration.inSeconds % 60} sec';
}
