import 'dart:async';

/// Collapses a burst of Realtime events into a single refresh.
///
/// Circle membership changes often arrive as several events in one transaction
/// (the invite row changes and the participant row is inserted). Refreshing on
/// each one would query the same data repeatedly, so callers schedule through
/// this helper instead.
class CircleRealtime {
  CircleRealtime({this.debounce = const Duration(milliseconds: 350)});

  final Duration debounce;
  Timer? _timer;

  void schedule(void Function() refresh) {
    _timer?.cancel();
    _timer = Timer(debounce, refresh);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isPending => _timer?.isActive ?? false;
}
