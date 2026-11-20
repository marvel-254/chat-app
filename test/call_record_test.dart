import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/models/call_record.dart';

CallRecord record(String status, {String? connected, String? ended}) =>
    CallRecord({
      'id': 'one',
      'conversation_id': 'dm',
      'caller_id': 'a',
      'callee_id': 'b',
      'video': false,
      'status': status,
      'started_at': '2026-11-20T00:00:00Z',
      'expires_at': '2026-11-20T00:00:45Z',
      'connected_at': connected,
      'ended_at': ended,
    });

void main() {
  test('direction, cancellation and unanswered calls are distinct', () {
    final missed = record('missed', ended: '2026-11-20T00:00:45Z');
    expect(missed.outcome('a'), 'Unanswered');
    expect(missed.outcome('b'), 'Missed');
    expect(missed.matches(CallFilter.outgoing, 'a'), isTrue);
    expect(missed.matches(CallFilter.incoming, 'b'), isTrue);
    expect(missed.matches(CallFilter.missed, 'a'), isFalse);
    expect(missed.matches(CallFilter.missed, 'b'), isTrue);
    expect(missed.duration, isNull);
    for (final value in ['cancelled', 'rejected', 'busy', 'failed']) {
      expect(record(value).matches(CallFilter.missed, 'b'), isFalse);
      expect(record(value).duration, isNull);
    }
  });
  test('duration is anchored to first connected time, not ringing', () {
    final completed = record('completed',
        connected: '2026-11-20T00:00:10Z', ended: '2026-11-20T00:02:44Z');
    expect(completed.outcome('b'), 'Completed');
    expect(completed.duration, const Duration(minutes: 2, seconds: 34));
    expect(CallRecord.formatDuration(completed.duration!), '2 min 34 sec');
    expect(
        record('completed',
                connected: '2026-11-20T00:00:10Z',
                ended: '2026-11-20T00:00:10Z')
            .duration,
        Duration.zero);
  });
}
