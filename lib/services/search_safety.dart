import '../models/profile.dart';

/// Strips PostgREST filter metacharacters from a user search string.
///
/// `.or('username.ilike.%$query%')` interpolates the term into a filter list
/// where `,`, `()`, and quotes start new clauses. Keep letters, numbers, and
/// the username alphabet (`.` `_` `-`) so people can still find `alex.vance`.
String sanitizeSearchTerm(String query, {int maxLength = 64}) {
  final cleaned = query
      .trim()
      .replaceFirst(RegExp(r'^@+'), '')
      .replaceAll(RegExp(r'[%*,()\\"]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
}

/// Ranks exact usernames first, then username prefixes, then other matches.
/// Merges separate prefix/contains queries without repeating a profile.
List<Profile> rankPeopleSearchResults(
  Iterable<Profile> matches,
  String term, {
  required int limit,
}) {
  final needle = term.toLowerCase();
  final seen = <String>{};
  final exact = <Profile>[];
  final prefixes = <Profile>[];
  final others = <Profile>[];
  for (final profile in matches) {
    if (!seen.add(profile.id)) continue;
    final username = profile.username.toLowerCase();
    if (username == needle) {
      exact.add(profile);
    } else if (username.startsWith(needle)) {
      prefixes.add(profile);
    } else {
      others.add(profile);
    }
  }
  return [...exact, ...prefixes, ...others].take(limit).toList();
}
