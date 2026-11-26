import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/services/call_state_machine.dart';

void main() {
  test('rejects impossible transitions without mutating state', () {
    final machine = CallStateMachine(initial: CallPhase.outgoing);
    expect(() => machine.transition(CallPhase.connected), returnsNormally);
    expect(() => machine.transition(CallPhase.incoming), throwsA(isA<InvalidCallTransition>()));
    expect(machine.state.phase, CallPhase.connected);
  });

  test('reconnection attempts are bounded and terminal states are final', () {
    final machine = CallStateMachine(initial: CallPhase.accepted);
    machine.transition(CallPhase.connected);
    machine.transition(CallPhase.reconnecting);
    machine.transition(CallPhase.connected);
    expect(machine.state.reconnectionAttempts, 1);
    expect(machine.shouldRetryReconnect, isTrue);
    machine.transition(CallPhase.reconnecting);
    machine.transition(CallPhase.connected);
    expect(machine.shouldRetryReconnect, isFalse);

    final terminal = CallStateMachine(initial: CallPhase.outgoing);
    terminal.transition(CallPhase.failed, reason: CallEndReason.permissionDenied);
    expect(terminal.state.isTerminal, isTrue);
    expect(terminal.state.endReason, CallEndReason.permissionDenied);
    expect(() => terminal.transition(CallPhase.connected), throwsA(isA<InvalidCallTransition>()));
  });

  test('maps call failures to end reasons', () {
    final machine = CallStateMachine(initial: CallPhase.incoming);
    expect(machine.reasonFor('Access denied'), CallEndReason.permissionDenied);
    expect(machine.reasonFor('No answer.'), CallEndReason.timeout);
    expect(machine.reasonFor('Could not connect the call.'), CallEndReason.networkFailure);
    expect(machine.reasonFor(null), CallEndReason.normalHangup);
  });
}
