/// Untrusted hints from FCM or the browser. Routing still checks membership.
class PushMessageTarget {
  const PushMessageTarget(
    this.conversationId,
    this.recipientUserId, {
    this.kind = 'message',
    this.callId,
    this.eventId,
  });

  final String conversationId, kind;
  final String? recipientUserId, callId, eventId;
  bool get isCall => callId != null;
  bool get incoming => kind == 'incoming_call';
  bool get missed => kind == 'missed_call';
  String get notice => switch (kind) {
        'incoming_call' => 'You have an incoming call.',
        'missed_call' => 'You missed a call.',
        'friendship_reminder' => 'A friendship anniversary is today.',
        _ => 'You have a new message.',
      };

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static bool isId(Object? value) => value is String && _uuid.hasMatch(value);

  static PushMessageTarget? fromData(Map<String, dynamic> data) {
    final conversation = data['conversation_id'];
    if (!isId(conversation)) return null;
    final recipient = data['recipient_user_id'];
    if (data.containsKey('recipient_user_id') && !isId(recipient)) return null;
    final kind = data['kind'] ?? 'message';
    if (!const {
      'message',
      'incoming_call',
      'missed_call',
      'friendship_reminder',
    }.contains(kind)) {
      return null;
    }
    final call = data['call_id'];
    final isCall = kind == 'incoming_call' || kind == 'missed_call';
    if (isCall && (!isId(call) || !isId(recipient))) return null;
    final event = data['event_id'];
    final expiry = data['expires_at'];
    if (expiry != null) {
      final deadline = expiry is String ? DateTime.tryParse(expiry) : null;
      if (deadline == null || !deadline.isAfter(DateTime.now())) return null;
    }
    return PushMessageTarget(
      (conversation as String).toLowerCase(),
      (recipient as String?)?.toLowerCase(),
      kind: kind as String,
      callId: isCall ? (call as String).toLowerCase() : null,
      eventId: event is String && event.length <= 80 ? event : null,
    );
  }
}
