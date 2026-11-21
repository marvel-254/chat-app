import 'package:flutter/material.dart';

import '../models/profile.dart';
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
