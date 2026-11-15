import 'profile.dart';

/// A message that has been dispatched optimistically before the server
/// acknowledges it. It carries enough state to render a pending (unsent)
/// bubble, retry a failed send, and flush itself when the connection
/// returns online.
///
/// Lifecycle of [status]:
///   sending -> sent   (the server echoed the row back)
///   sending -> failed (network or server error) -> queued -> sending (on reconnect)
///   sent    -> (terminal)
class PendingMessage {
  final String localId;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? replyToId;

  /// How the message is currently progressing to the peer.
  /// One of: sending, sent, failed, queued.
  String status;
  int retryCount;

  PendingMessage({
    required this.localId,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.expiresAt,
    this.replyToId,
    this.status = 'sending',
    this.retryCount = 0,
  });

  /// The optimistic [Message] rendered for this send while in flight.
  Message toOptimisticMessage() {
    return Message(
      id: localId,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      createdAt: createdAt,
      readAt: null,
      expiresAt: expiresAt,
      replyToId: replyToId,
      reactions: const [],
    );
  }

  /// A sensible baseline expiry: a generous default so a queued message
  /// doesn't evaporate before it can be retried.
  static Duration? defaultExpiry() => const Duration(hours: 24);

  PendingMessage copyWith({
    String? localId,
    String? conversationId,
    String? senderId,
    String? content,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? replyToId,
    String? status,
    int? retryCount,
  }) {
    return PendingMessage(
      localId: localId ?? this.localId,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      replyToId: replyToId ?? this.replyToId,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  String toString() =>
      'PendingMessage(localId=$localId, status=$status, retryCount=$retryCount, content=${content.substring(0, 30)}…)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingMessage &&
          runtimeType == other.runtimeType &&
          localId == other.localId;

  @override
  int get hashCode => localId.hashCode;
}
