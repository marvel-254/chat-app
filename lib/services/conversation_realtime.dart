import 'dart:async';

/// Collapses bursts of conversation Realtime events into one refetch.
class ConversationRealtime {
  ConversationRealtime({this.debounce = const Duration(milliseconds: 350)});

  final Duration debounce;
  Timer? _timer;

  bool get isPending => _timer?.isActive ?? false;

  void schedule(void Function() action) {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
