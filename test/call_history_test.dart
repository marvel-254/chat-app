import 'package:flutter_test/flutter_test.dart';

import 'package:bro_chat/models/call_history.dart' as history;
import 'package:bro_chat/services/push_message_target.dart';

void main() {
  group('call history domain', () {
    test('formats human-readable durations', () {
      expect(history.formatCallDuration(0), 'Under a second');
      expect(history.formatCallDuration(24), '24 sec');
      expect(history.formatCallDuration(60), '1 min');
      expect(history.formatCallDuration(154), '2 min 34 sec');
    });

    test('distinguishes every final call outcome', () {
      expect(
        history.resolveCallStatus(
          outgoing: true,
          answered: true,
          localHangup: false,
          peerHangup: false,
        ),
        history.CallRecord.statusCompleted,
      );
      expect(
        history.resolveCallStatus(
          outgoing: true,
          answered: false,
          localHangup: true,
          peerHangup: false,
        ),
        history.CallRecord.statusCancelled,
      );
      expect(
        history.resolveCallStatus(
          outgoing: true,
          answered: false,
          localHangup: false,
          peerHangup: true,
        ),
        history.CallRecord.statusUnanswered,
      );
      expect(
        history.resolveCallStatus(
          outgoing: false,
          answered: false,
          localHangup: true,
          peerHangup: false,
        ),
        history.CallRecord.statusRejected,
      );
      expect(
        history.resolveCallStatus(
          outgoing: false,
          answered: false,
          localHangup: false,
          peerHangup: true,
        ),
        history.CallRecord.statusMissed,
      );
      expect(
        history.resolveCallStatus(
          outgoing: false,
          answered: false,
          localHangup: false,
          peerHangup: false,
          reason: 'timeout',
        ),
        history.CallRecord.statusMissed,
      );
      expect(
        history.resolveCallStatus(
          outgoing: true,
          answered: true,
          localHangup: false,
          peerHangup: false,
          reason: 'networkFailure',
        ),
        history.CallRecord.statusFailed,
      );
    });

    test('cancelled calls are never missed calls', () {
      final cancelled = history.CallRecord(
        id: 'row',
        callId: 'call',
        conversationId: 'conv',
        peerUserId: 'peer',
        kind: history.CallRecord.kindVoice,
        direction: history.CallRecord.directionOutgoing,
        status: history.CallRecord.statusCancelled,
        startedAt: DateTime.utc(2026, 11, 21, 10),
      );
      expect(cancelled.isMissed, isFalse);
      expect(cancelled.hasDuration, isFalse);
    });

    test('deduplicates late and repeated signalling by call id', () {
      final first = history.CallRecord(
        id: 'one',
        callId: 'call-1',
        conversationId: 'conv',
        peerUserId: 'peer',
        kind: history.CallRecord.kindVoice,
        direction: history.CallRecord.directionOutgoing,
        status: history.CallRecord.statusCompleted,
        startedAt: DateTime.utc(2026, 11, 21, 10),
        connectedAt: DateTime.utc(2026, 11, 21, 10, 0, 2),
        durationSeconds: 154,
      );
      final duplicate = first.copyWith(status: history.CallRecord.statusFailed);
      final later = history.CallRecord(
        id: 'two',
        callId: 'call-2',
        conversationId: 'conv',
        peerUserId: 'peer',
        kind: history.CallRecord.kindVideo,
        direction: history.CallRecord.directionIncoming,
        status: history.CallRecord.statusMissed,
        startedAt: DateTime.utc(2026, 11, 21, 9),
      );
      final result = history.dedupeCallRecords([duplicate, later, first]);
      expect(result, hasLength(2));
      expect(result.first.callId, 'call-1');
      expect(result.first.status, history.CallRecord.statusCompleted);
      expect(result.first.durationSeconds, 154);
    });
  });

  group('missed call notification routing', () {
    test('parses only valid missed-call payloads', () {
      final target = PushMessageTarget.fromData({
        'conversation_id': '89a4d0d1-08a5-4c2f-9a41-1b4f30ec5f2a',
        'call_id': '2d3a6f60-2f4f-4d2f-9b0a-6dfe7a4cd1e1',
        'kind': 'missed_call',
      });
      expect(target, isNotNull);
      expect(target!.isMissedCall, isTrue);
      expect(target.callId, '2d3a6f60-2f4f-4d2f-9b0a-6dfe7a4cd1e1');
    });

    test('rejects malformed call ids', () {
      expect(
        PushMessageTarget.fromData({
          'conversation_id': '89a4d0d1-08a5-4c2f-9a41-1b4f30ec5f2a',
          'call_id': 'not-a-uuid',
          'kind': 'missed_call',
        })?.isMissedCall,
        isFalse,
      );
    });
  });
}
