import 'package:flutter/material.dart';

import '../models/avatar_config.dart';
import '../models/profile.dart';
import '../screens/chat/widgets/avatar.dart';
import '../theme/app_colors.dart' as app_colors;

/// Returns the id of the first inbound message that was unread when the chat
/// was opened, or null when every inbound message had already been read.
String? firstUnreadInboundMessageId(
  List<Message> messages,
  String currentUserId,
) {
  for (final message in messages) {
    if (message.senderId != currentUserId && message.readAt == null) {
      return message.id;
    }
  }
  return null;
}

/// A subtle divider marking where unread messages started.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key, this.label = 'New messages'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(
        color: app_colors.P.primary.withValues(alpha: 0.35),
        height: 1,
        thickness: 1,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: app_colors.P.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}


/// Only the last bubble of an inbound group carries a peer photo. Groups with
/// several participants have no single peer, so nothing is shown there.
bool showMessageBubbleAvatar({
  required bool mine,
  required bool groupedNext,
  required String? peerId,
  required String senderId,
}) =>
    !mine &&
    !groupedNext &&
    peerId != null &&
    peerId.isNotEmpty &&
    senderId == peerId;

/// Small peer avatar aligned with the bottom of an incoming message bubble.
class MessageBubbleAvatar extends StatelessWidget {
  const MessageBubbleAvatar({
    super.key,
    required this.name,
    this.url,
    this.digitalConfig,
    this.size = 28,
  });

  final String name;
  final String? url;
  final AvatarConfig? digitalConfig;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 2),
        child: Avatar(
          name: name,
          url: url,
          digitalConfig: digitalConfig,
          size: size,
        ),
      );
}
