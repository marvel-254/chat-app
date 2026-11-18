import 'package:bro_chat/services/people_search_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('deduplicates queries and stores the most recent form first', () async {
    await PeopleSearchHistory.record('alice', 'Alex');
    await PeopleSearchHistory.record('alice', 'Jess');
    await PeopleSearchHistory.record('alice', '  @alex  ');
    await PeopleSearchHistory.record('alice', '@');

    expect(await PeopleSearchHistory.load('alice'), ['@alex', 'Jess']);
  });

  test('caps history and clears only the specified account', () async {
    for (var i = 0; i < PeopleSearchHistory.maxEntries + 2; i++) {
      await PeopleSearchHistory.record('alice', 'person$i');
    }
    await PeopleSearchHistory.record('bob', 'another');
    await PeopleSearchHistory.remember(null, 'signed-out');

    final history = await PeopleSearchHistory.load('alice');
    expect(history, hasLength(PeopleSearchHistory.maxEntries));
    expect(history.first, 'person${PeopleSearchHistory.maxEntries + 1}');
    expect(history.last, 'person2');

    await PeopleSearchHistory.clear('alice');
    expect(await PeopleSearchHistory.load('alice'), isEmpty);
    expect(await PeopleSearchHistory.load('bob'), ['another']);
  });
}
