import 'dart:async';

import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/screens/status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<StatusPost> _feed() {
  final now = DateTime.now();
  return [
    StatusPost(
      id: 'one',
      userId: 'peer-1',
      content: 'A short update',
      createdAt: now.subtract(const Duration(minutes: 5)),
      expiresAt: now.add(const Duration(hours: 20)),
    ),
    StatusPost(
      id: 'two',
      userId: 'peer-2',
      content: 'Another update',
      createdAt: now.subtract(const Duration(minutes: 2)),
      expiresAt: now.add(const Duration(hours: 22)),
    ),
  ];
}

Future<void> _pumpFeed(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StatusScreen(
        watchStatuses: () => Stream.value(_feed()),
        currentUserId: () => 'me',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('status feed keeps a vertical list on compact screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpFeed(tester);

    expect(find.byType(ListView), findsWidgets);
    expect(find.byType(GridView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status feed uses a constrained grid on wide desktop',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpFeed(tester);

    expect(find.byType(GridView), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.maxCrossAxisExtent, 360);
    expect(tester.takeException(), isNull);
  });
}
