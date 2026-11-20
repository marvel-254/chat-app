import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/models/call_history.dart' as history;
import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/screens/calls/recent_calls_screen.dart';
import 'package:bro_chat/services/call_history.dart';

class _FakeCallHistory implements CallHistorySource {
  final List<history.CallRecord> records;
  final StreamController<CallHistorySnapshot> _controller;

  _FakeCallHistory(this.records)
      : _controller = StreamController<CallHistorySnapshot>.broadcast() {
    _controller.onListen = () {
      _controller.add(CallHistorySnapshot(records));
    };
  }

  @override
  Stream<CallHistorySnapshot> watch() => _controller.stream;

  @override
  Future<List<history.CallRecord>> cached() async => records;

  @override
  Future<history.CallRecord?> find(String callId) async {
    for (final record in records) {
      if (record.callId == callId) return record;
    }
    return null;
  }

  @override
  Future<void> record(history.CallRecord record) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> flushPending() async {}
}

Profile _peer(String id, {String label = 'Gideon'}) => Profile(
      id: id,
      username: 'gideon',
      displayName: label,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      photoVisibility: 'everyone',
      statusVisibility: 'everyone',
      aboutVisibility: 'everyone',
      readReceiptsEnabled: true,
    );

history.CallRecord _record({
  required String id,
  required String callId,
  required String direction,
  required String status,
  DateTime? startedAt,
}) =>
    history.CallRecord(
      id: id,
      callId: callId,
      conversationId: '89a4d0d1-08a5-4c2f-9a41-1b4f30ec5f2a',
      peerUserId: 'peer-1',
      kind: history.CallRecord.kindVoice,
      direction: direction,
      status: status,
      startedAt: startedAt ?? DateTime.utc(2026, 11, 21, 10),
      connectedAt: status == history.CallRecord.statusCompleted
          ? DateTime.utc(2026, 11, 21, 10, 0, 2)
          : null,
      durationSeconds: status == history.CallRecord.statusCompleted ? 154 : 0,
    );

void main() {
  testWidgets('recent calls screen renders entries and filters',
      (tester) async {
    final source = _FakeCallHistory([
      _record(
        id: '1',
        callId: 'call-1',
        direction: history.CallRecord.directionIncoming,
        status: history.CallRecord.statusMissed,
      ),
      _record(
        id: '2',
        callId: 'call-2',
        direction: history.CallRecord.directionOutgoing,
        status: history.CallRecord.statusCompleted,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: RecentCallsScreen(
        source: source,
        peerResolver: (id) async => _peer(id),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Recent Calls'), findsOneWidget);
    expect(find.text('Gideon'), findsNWidgets(2));
    expect(find.textContaining('Missed'), findsWidgets);

    await tester.tap(find.text('Missed'));
    await tester.pumpAndSettle();
    expect(find.text('Gideon'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('call-call-1')));
    await tester.pumpAndSettle();
    expect(find.text('Call details'), findsOneWidget);
  });

  testWidgets('empty state appears when there are no calls', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecentCallsScreen(
        source: _FakeCallHistory(const []),
        peerResolver: (id) async => _peer(id),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No calls yet'), findsOneWidget);
  });
}
