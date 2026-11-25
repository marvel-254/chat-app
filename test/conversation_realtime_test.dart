import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/services/conversation_realtime.dart';

void main() {
  test('a burst of events produces one refresh', () async {
    final debouncer =
        ConversationRealtime(debounce: const Duration(milliseconds: 10));
    var refreshes = 0;
    for (var i = 0; i < 6; i++) {
      debouncer.schedule(() => refreshes++);
    }
    expect(refreshes, 0);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(refreshes, 1);
  });

  test('cancel drops a scheduled refresh', () async {
    final debouncer =
        ConversationRealtime(debounce: const Duration(milliseconds: 10));
    var refreshes = 0;
    debouncer.schedule(() => refreshes++);
    expect(debouncer.isPending, isTrue);
    debouncer.cancel();
    expect(debouncer.isPending, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(refreshes, 0);
  });
}
