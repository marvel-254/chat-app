/// Strips PostgREST filter metacharacters from a user search string.
///
/// `.or('username.ilike.%$query%')` interpolates the term into a filter list
/// where `,`, `()`, and quotes start new clauses. Keep letters, numbers, and
/// the username alphabet (`.` `_` `-`) so people can still find `alex.vance`.
String sanitizeSearchTerm(String query, {int maxLength = 64}) {
  final cleaned = query
      .trim()
      .replaceAll(RegExp(r'[%*,()\\"]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
}
