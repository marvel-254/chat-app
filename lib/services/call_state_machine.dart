/// Typed WebRTC call state machine for BRO.
///
/// The UI must not invent states or allow a call to remain in a transient
/// state indefinitely. Every transition is validated and terminal states are
/// exhaustive.
library;

enum CallPhase {
  outgoing,
  incoming,
  ringing,
  accepted,
  connected,
  reconnecting,
  ended,
  failed,
}

enum CallEndReason {
  rejected,
  busy,
  cancelled,
  timeout,
  networkFailure,
  normalHangup,
  permissionDenied,
}

class CallState {
  const CallState({
    required this.phase,
    this.endReason,
    this.reconnectionAttempts = 0,
  });

  final CallPhase phase;
  final CallEndReason? endReason;
  final int reconnectionAttempts;

  bool get isTerminal =>
      phase == CallPhase.ended || phase == CallPhase.failed;

  CallState copyWith({
    CallPhase? phase,
    CallEndReason? endReason,
    int? reconnectionAttempts,
  }) =>
      CallState(
        phase: phase ?? this.phase,
        endReason: endReason ?? this.endReason,
        reconnectionAttempts: reconnectionAttempts ?? this.reconnectionAttempts,
      );
}

class InvalidCallTransition implements Exception {
  const InvalidCallTransition(this.from, this.to);

  final CallPhase from;
  final CallPhase to;

  @override
  String toString() => 'InvalidCallTransition($from -> $to)';
}

/// Pure, testable transition rules.
class CallStateMachine {
  CallStateMachine({this.maxReconnectAttempts = 2, CallPhase initial = CallPhase.incoming})
      : _state = CallState(phase: initial);

  final int maxReconnectAttempts;

  static const _allowed = <CallPhase, Set<CallPhase>>{
    CallPhase.outgoing: {
      CallPhase.ringing,
      CallPhase.connected,
      CallPhase.ended,
      CallPhase.failed,
      CallPhase.reconnecting,
    },
    CallPhase.incoming: {
      CallPhase.ringing,
      CallPhase.accepted,
      CallPhase.ended,
      CallPhase.failed,
    },
    CallPhase.ringing: {
      CallPhase.accepted,
      CallPhase.connected,
      CallPhase.ended,
      CallPhase.failed,
    },
    CallPhase.accepted: {
      CallPhase.connected,
      CallPhase.ended,
      CallPhase.failed,
      CallPhase.reconnecting,
    },
    CallPhase.connected: {
      CallPhase.reconnecting,
      CallPhase.ended,
      CallPhase.failed,
    },
    // Reconnecting is bounded; a repeated failure terminates the call.
    CallPhase.reconnecting: {
      CallPhase.connected,
      CallPhase.ended,
      CallPhase.failed,
    },
    CallPhase.ended: {},
    CallPhase.failed: {},
  };

  CallState _state;

  CallState get state => _state;

  CallState transition(CallPhase to, {CallEndReason? reason}) {
    if (!_allowed[_state.phase]!.contains(to)) {
      throw InvalidCallTransition(_state.phase, to);
    }
    if (to == CallPhase.reconnecting &&
        _state.reconnectionAttempts >= maxReconnectAttempts) {
      _state = CallState(
        phase: CallPhase.failed,
        endReason: CallEndReason.networkFailure,
        reconnectionAttempts: _state.reconnectionAttempts,
      );
      return _state;
    }
    _state = CallState(
      phase: to,
      endReason: _isTerminal(to) ? (reason ?? _state.endReason) : null,
      reconnectionAttempts: to == CallPhase.reconnecting
          ? _state.reconnectionAttempts + 1
          : _state.reconnectionAttempts,
    );
    return _state;
  }

  bool get shouldRetryReconnect =>
      _state.phase != CallPhase.failed &&
      _state.reconnectionAttempts < maxReconnectAttempts;

  static bool _isTerminal(CallPhase phase) =>
      phase == CallPhase.ended || phase == CallPhase.failed;
}
