import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/models/circle.dart';
import 'package:bro_chat/widgets/circle_invite_tile.dart';

void main() {
  final invite = CircleInvite(
    id: 'invite-1',
    circleId: 'circle-1',
    circleName: 'Studio Circle',
    inviterName: 'Alice',
    createdAt: DateTime.utc(2026, 11, 23),
  );

  testWidgets('join and decline report the same invitation', (tester) async {
    String? action;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CircleInviteTile(
          invite: invite,
          onAccept: () => action = 'join',
          onDecline: () => action = 'decline',
        ),
      ),
    ));

    expect(find.text('Studio Circle'), findsOneWidget);
    expect(find.text('From Alice'), findsOneWidget);
    expect(find.byKey(const ValueKey('invite-1')), findsOneWidget);

    await tester.tap(find.text('Decline'));
    expect(action, 'decline');
    await tester.tap(find.text('Join'));
    expect(action, 'join');
  });
}
