import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/screens/status_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openViewer(WidgetTester tester, List<String> viewed) async {
  final now = DateTime.now();
  await tester.pumpWidget(MaterialApp(
    home: StatusViewerScreen(
      userId: 'peer',
      currentUserId: () => 'me',
      loadStatuses: () async => [
        StatusPost(
          id: 'first',
          userId: 'peer',
          content: 'First status',
          createdAt: now.subtract(const Duration(minutes: 1)),
          expiresAt: now.add(const Duration(hours: 47)),
        ),
        StatusPost(
          id: 'second',
          userId: 'peer',
          content: 'Second status',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 48)),
        ),
      ],
      recordView: (id) async {
        viewed.add(id);
      },
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('each status gets two minutes and thirty seconds', (tester) async {
    final viewed = <String>[];
    await _openViewer(tester, viewed);

    await tester.pump(const Duration(minutes: 2, seconds: 29));
    expect(find.text('First status'), findsOneWidget);
    expect(viewed, ['first']);

    // Allow a frame on the far side of the animation boundary.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Second status'), findsOneWidget);
    expect(viewed, ['first', 'second']);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Second status'), findsOneWidget);
  });

  testWidgets('holding pauses the timeout and tapping still skips', (tester) async {
    final viewed = <String>[];
    await _openViewer(tester, viewed);
    final nextSide = tester.getCenter(find.byType(Scaffold)) + const Offset(80, 0);
    final gesture = await tester.startGesture(nextSide);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(minutes: 3));
    expect(find.text('First status'), findsOneWidget);
    expect(viewed, ['first']);

    await gesture.up();
    await tester.pump();
    await tester.tapAt(nextSide);
    await tester.pump();
    expect(find.text('Second status'), findsOneWidget);
    expect(viewed, ['first', 'second']);
  });
}
