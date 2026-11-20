import 'package:bro_chat/services/call_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('call state machine', () {
    test('outgoing call progresses through ringing to connected', () {
      final machine = CallStateMachine(initial: CallPhase.outgoing);
      expect(machine.transition(CallPhase.ringing).phase, CallPhase.ringing);
      expect(machine.transition(CallPhase.connected).phase, CallPhase.connected);
      expect(machine.state.isTerminal, isFalse);
    });

    test('invalid transitions are rejected', () {
      final machine = CallStateMachine(initial: CallPhase.ended);
      expect(
        () => machine.transition(CallPhase.ringing),
        throwsA(isA<InvalidCallTransition>()),
      );
    });

    test('reconnect attempts are bounded', () {
      final machine = CallStateMachine(
        initial: CallPhase.connected,
        maxReconnectAttempts: 2,
      );
      expect(machine.transition(CallPhase.reconnecting).phase,
          CallPhase.reconnecting);
      expect(machine.transition(CallPhase.connected).phase, CallPhase.connected);
      expect(machine.transition(CallPhase.reconnecting).phase,
          CallPhase.reconnecting);
      expect(machine.transition(CallPhase.connected).phase, CallPhase.connected);
      final failed = machine.transition(CallPhase.reconnecting);
      expect(failed.phase, CallPhase.failed);
      expect(failed.endReason, CallEndReason.networkFailure);
      expect(machine.shouldRetryReconnect, isFalse);
    });

    test('terminal reasons are preserved', () {
      final machine = CallStateMachine(initial: CallPhase.ringing);
      final state = machine.transition(
        CallPhase.ended,
        reason: CallEndReason.timeout,
      );
      expect(state.endReason, CallEndReason.timeout);
      expect(state.isTerminal, isTrue);
    });
  });
}
