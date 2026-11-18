import 'package:shared_preferences/shared_preferences.dart';

import 'search_safety.dart';

/// Search history is local to this app install/browser and partitioned by user.
class PeopleSearchHistory {
  static const maxEntries = 8;
  static String _key(String accountId) =>
      'bro.people_search_history.v1.$accountId';

  static Future<List<String>> load(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(accountId)) ?? const [];
  }

  static Future<void> record(String accountId, String query) async {
    final term = sanitizeSearchTerm(query);
    if (term.isEmpty) return;
    final entry = query.trim().startsWith('@') ? '@$term' : term;
    final dedupKey = term.toLowerCase();
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key(accountId)) ?? const <String>[];
    await prefs.setStringList(
      _key(accountId),
      [
        entry,
        ...history.where(
            (item) => sanitizeSearchTerm(item).toLowerCase() != dedupKey),
      ].take(maxEntries).toList(),
    );
  }

  /// History is optional: unavailable local storage must not break search.
  static Future<void> remember(String? accountId, String query) async {
    if (accountId == null) return;
    try {
      await record(accountId, query);
    } catch (_) {
      // Searching and starting chats should still work.
    }
  }

  static Future<void> clear(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(accountId));
  }
}
