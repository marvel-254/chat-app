import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/call_record.dart';
import 'supabase.dart';

class Calls {
  static const timeout = Duration(seconds: 8);
  static const _storage = FlutterSecureStorage();
  static String newId() => const Uuid().v4();
  static String route(
    String conversation,
    String id,
    bool video,
    bool outgoing,
  ) =>
      '/call/$conversation?id=$id&video=$video&outgoing=$outgoing';

  static Future<CallRecord> start(
    String id,
    String conversation,
    String peer,
    bool video,
  ) async {
    try {
      return _record(
        await Supa.client.rpc(
          'start_bro_call',
          params: {
            'p_id': id,
            'p_conversation': conversation,
            'p_peer': peer,
            'p_video': video,
          },
        ).timeout(timeout),
      );
    } catch (e) {
      debugPrint('Calls.start failed: $e');
      await Sentry.captureException(e);
      rethrow;
    }
  }

  static DateTime? _lastRefreshAttempt;

  /// Returns `true` when [error] is an expired-JWT PostgREST error (`PGRST303`).
  @visibleForTesting
  static bool isJwtExpiredError(Object error) {
    return error is PostgrestException &&
        (error.code == 'PGRST303' ||
            error.message.toLowerCase().contains('jwt expired'));
  }

  /// Returns `true` for transient background-poll failures (timeouts / stale
  /// JWTs) that should be logged and recovered rather than reported to Sentry.
  @visibleForTesting
  static bool isTransientNetworkError(Object error) {
    return error is TimeoutException || isJwtExpiredError(error);
  }

  static Future<void> _handleCallError(String op, Object error) async {
    debugPrint('$op failed: $error');
    if (isJwtExpiredError(error)) {
      final now = DateTime.now();
      if (_lastRefreshAttempt == null ||
          now.difference(_lastRefreshAttempt!) > const Duration(seconds: 10)) {
        _lastRefreshAttempt = now;
        try {
          await Supa.client.auth.refreshSession();
        } catch (_) {}
      }
      return;
    }
    if (error is TimeoutException) return;
    await Sentry.captureException(error);
  }

  static Future<CallRecord> advance(String id, String action) async {
    try {
      return _record(
        await Supa.client.rpc('advance_bro_call',
            params: {'p_id': id, 'p_action': action}).timeout(timeout),
      );
    } catch (e) {
      await _handleCallError('Calls.advance', e);
      rethrow;
    }
  }

  static Future<CallRecord?> incoming(String owner) async {
    try {
      final rows = await Supa.client
          .from('call_sessions')
          .select()
          .eq('callee_id', owner)
          .eq('status', 'ringing')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .timeout(timeout);
      return rows.isEmpty ? null : _record(rows.first);
    } catch (e) {
      await _handleCallError('Calls.incoming', e);
      rethrow;
    }
  }

  static Future<CallRecord?> get(String id) async {
    try {
      final row = await Supa.client
          .from('call_sessions')
          .select()
          .eq('id', id)
          .maybeSingle()
          .timeout(timeout);
      return row == null ? null : _record(row);
    } catch (e) {
      await _handleCallError('Calls.get', e);
      rethrow;
    }
  }

  static const _cacheKeyPrefix = 'recent_calls_v2_';
  static const _timestampKeyPrefix = 'recent_calls_ts_v2_';
  static String _key(String owner) => '$_cacheKeyPrefix$owner';
  static String _tsKey(String owner) => '$_timestampKeyPrefix$owner';
  static const Duration _cacheTtl = Duration(minutes: 5);

  static Future<List<CallRecord>> cached(String owner) async {
    try {
      // Check TTL — only return cached data if it's less than 5 minutes old
      final tsRaw = await _storage.read(key: _tsKey(owner));
      if (tsRaw != null) {
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(int.parse(tsRaw));
        if (DateTime.now().difference(cachedAt) > _cacheTtl) {
          debugPrint('Calls.cached: cache expired for $owner, skipping');
          return [];
        }
      }
      final raw = await _storage.read(key: _key(owner));
      if (raw == null) return [];
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      return (jsonDecode(raw) as List)
          .map(_record)
          .where(
            (record) =>
                record.startedAt.isAfter(cutoff) &&
                (record.callerId == owner || record.calleeId == owner),
          )
          .toList();
    } catch (e) {
      debugPrint('Calls.cached failed: $e');
      await Sentry.captureException(e);
      return [];
    }
  }

  static Future<List<CallRecord>> recent(String owner) async {
    _requireOwner(owner);
    try {
      final rows = await Supa.client
          .from('call_sessions')
          .select()
          .or(
              'and(caller_id.eq.$owner,ended_at.not.is.null),and(callee_id.eq.$owner,ended_at.not.is.null)')
          .order('started_at', ascending: false)
          .order('id')
          .limit(100)
          .timeout(timeout);
      _requireOwner(owner);
      return rows.map(_record).toList();
    } catch (e) {
      debugPrint('Calls.recent failed: $e');
      await Sentry.captureException(e);
      rethrow;
    }
  }

  static Future<void> hide(String owner, String? id) async {
    _requireOwner(owner);
    await Supa.client
        .rpc('hide_bro_calls', params: {'p_id': id}).timeout(timeout);
    _requireOwner(owner);
    final records = id == null ? <CallRecord>[] : await cached(owner);
    await _cache(owner, records.where((record) => record.id != id).toList());
  }

  static Future<void> cache(String owner, List<CallRecord> records) async {
    _requireOwner(owner);
    await _cache(owner, records);
  }

  static Future<void> _cache(String owner, List<CallRecord> records) async {
    try {
      await _storage.write(
        key: _key(owner),
        value: jsonEncode(records.map((r) => r.json).toList()),
      );
      // Store timestamp for TTL check
      await _storage.write(
        key: _tsKey(owner),
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      debugPrint('Calls._cache failed: $e');
      // Storage may be unavailable in restricted browsing contexts.
    }
  }

  static void _requireOwner(String owner) {
    if (Supa.currentUser?.id != owner) throw StateError('Account changed');
  }

  static CallRecord _record(dynamic row) =>
      CallRecord(Map<String, dynamic>.from(row as Map));
}
