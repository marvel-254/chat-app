import 'package:bro_chat/services/crypto/revision_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same-row edit replay cannot lower the high water mark', () async {
    var latest = 0;
    Future<void> observe(int n) =>
        RevisionGuard.observe('message', n, () async => latest, (v) async {
          latest = v;
        });
    final first = observe(2);
    final replay = expectLater(observe(1), throwsStateError);
    await Future.wait([first, replay]);
    await observe(2);
    await observe(3);
    expect(latest, 3);
  });
}
