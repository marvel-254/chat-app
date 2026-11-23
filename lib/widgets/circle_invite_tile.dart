import 'package:flutter/material.dart';
import '../models/circle.dart';
import '../theme/app_colors.dart' as app_colors;

class CircleInviteTile extends StatelessWidget {
  final CircleInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const CircleInviteTile({
    super.key,
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey(invite.id),
      leading: const Icon(Icons.mail_outline, color: app_colors.P.primary),
      title: Text(invite.circleName,
          style: const TextStyle(color: app_colors.P.text)),
      subtitle: Text('From ${invite.inviterName}',
          style: const TextStyle(color: app_colors.P.muted, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: onDecline, child: const Text('Decline')),
          FilledButton(onPressed: onAccept, child: const Text('Join')),
        ],
      ),
    );
  }
}
