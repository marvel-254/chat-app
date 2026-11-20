/// After signature verification, reject rollbacks relative to revisions this
/// installation has seen. A new device cannot infer withheld history.
class RevisionGuard {
  static final _pending = <String, Future<void>>{};
  static Future<void> observe(String key, int revision,
      Future<int> Function() load, Future<void> Function(int) save) {
    final previous = _pending[key] ?? Future<void>.value();
    final task = previous.catchError((_) {}).then((_) async {
      final latest = await load();
      if (revision < latest) throw StateError('Older signed message revision');
      if (revision > latest) await save(revision);
    });
    _pending[key] = task;
    return task.whenComplete(() {
      if (identical(_pending[key], task)) _pending.remove(key);
    });
  }
}
