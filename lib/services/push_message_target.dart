/// Parse only known database IDs from Firebase data before routing.
class PushMessageTarget {
  const PushMessageTarget(
    this.conversationId,
    this.recipientUserId, {
    this.callId,
    this.isMissedCall = false,
  });

  final String conversationId;
  final String? recipientUserId;
  final String? callId;
  final bool isMissedCall;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static PushMessageTarget? fromData(Map<String, dynamic> data) {
    final conversation = data['conversation_id'];
    if (conversation is! String || !_uuid.hasMatch(conversation)) return null;
    final recipient = data['recipient_user_id'];
    if (data.containsKey('recipient_user_id')) {
      if (recipient is! String || !_uuid.hasMatch(recipient)) return null;
      return PushMessageTarget(
        conversation.toLowerCase(),
        recipient.toLowerCase(),
      );
    }

    final rawCallId = data['call_id'];
    final callId = rawCallId is String && _uuid.hasMatch(rawCallId)
        ? rawCallId.toLowerCase()
        : null;
    final missed = data['kind'] == 'missed_call' && callId != null;
    // Older queued notifications lack a recipient. The client must check
    // membership under the current session before opening their conversation.
    return PushMessageTarget(
      conversation.toLowerCase(),
      null,
      callId: missed ? callId : null,
      isMissedCall: missed,
    );
  }
}
