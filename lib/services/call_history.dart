import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/call_history.dart';
import 'supabase.dart';

/// UI-facing snapshot so the screen can render offline/error states without
/// reaching into Supabase itself.
class CallHistorySnapshot {
  const CallHistorySnapshot(
    this.records, {
    this.isOffline = false,
    this.error,
  });

  final List<CallRecord> records;
  final bool isOffline;
  final String? error;
}

/// Injectable source keeps the Recent Calls widget testable without Supabase.
abstract class CallHistorySource {
  Stream<CallHistorySnapshot> watch();
  Future<List<CallRecord>> cached();
  Future<CallRecord?> find(String callId);
  Future<void> record(CallRecord record);
  Future<void> delete(String id);
  Future<void> clear();
  Future<void> flushPending();
}

class CallHistory implements CallHistorySource {
  CallHistory({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _cacheKey = 'bro.call_history.cache.v1';
  static const _pendingKey = 'bro.call_history.pending.v1';

  String? get _userId => Supa.currentUser?.id;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<List<CallRecord>> cached() async {
    final prefs = await _prefs;
    return _decode(prefs.getStringList(_cacheKey) ?? const <String>[]);
  }

  List<CallRecord> _decode(List<String> encoded) {
    final result = <CallRecord>[];
    for (final value in encoded) {
      try {
        result.add(CallRecord.fromJson(jsonDecode(value) as Map<String, dynamic>));
      } catch (_) {
        // A corrupt cache entry is dropped rather than breaking the screen.
      }
    }
    return dedupeCallRecords(result);
  }

  Future<void> _writeCache(List<CallRecord> records) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      _cacheKey,
      dedupeCallRecords(records).map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  @override
  Stream<CallHistorySnapshot> watch() async* {
    unawaited(flushPending());
    final local = await cached();
    yield CallHistorySnapshot(local, isOffline: true);

    final uid = _userId;
    if (uid == null) {
      yield const CallHistorySnapshot(<CallRecord>[], isOffline: true);
      return;
    }

    try {
      await for (final rows in _client
          .from('call_history')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .order('started_at', ascending: false)) {
        final remote = dedupeCallRecords(
          (rows as List)
              .map((row) => CallRecord.fromJson(Map<String, dynamic>.from(row))),
        );
        await _writeCache(remote);
        yield CallHistorySnapshot(remote);
      }
    } catch (_) {
      yield CallHistorySnapshot(
        local,
        isOffline: true,
        error: 'Call history is unavailable right now. Showing saved calls.',
      );
    }
  }

  @override
  Future<CallRecord?> find(String callId) async {
    final all = await cached();
    for (final record in all) {
      if (record.callId == callId) return record;
    }
    final uid = _userId;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('call_history')
          .select()
          .eq('user_id', uid)
          .eq('call_id', callId)
          .maybeSingle();
      return row == null
          ? null
          : CallRecord.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> record(CallRecord record) async {
    final uid = _userId;
    if (uid == null) return;
    final payload = record.toJson()..['user_id'] = uid;
    try {
      await _client
          .from('call_history')
          .upsert(payload, onConflict: 'user_id,call_id');
    } catch (_) {
      await _enqueue(payload);
    }
    final local = await cached();
    await _writeCache([...local, record]);
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final prefs = await _prefs;
    final pending = prefs.getStringList(_pendingKey) ?? <String>[];
    pending.add(jsonEncode(payload));
    await prefs.setStringList(_pendingKey, pending);
  }

  @override
  Future<void> flushPending() async {
    final uid = _userId;
    if (uid == null) return;
    final prefs = await _prefs;
    final pending = prefs.getStringList(_pendingKey) ?? <String>[];
    if (pending.isEmpty) return;
    final remaining = <String>[];
    for (final value in pending) {
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(value));
        await _client
            .from('call_history')
            .upsert(payload, onConflict: 'user_id,call_id');
      } catch (_) {
        remaining.add(value);
      }
    }
    await prefs.setStringList(_pendingKey, remaining);
  }

  @override
  Future<void> delete(String id) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _client.from('call_history').delete().eq('user_id', uid).eq('id', id);
    } catch (_) {
      // The local cache is still updated below; the row is retried on sync.
    }
    final local = await cached();
    await _writeCache(local.where((r) => r.id != id).toList());
  }

  @override
  Future<void> clear() async {
    final uid = _userId;
    if (uid != null) {
      try {
        await _client.from('call_history').delete().eq('user_id', uid);
      } catch (_) {
        // Clearing offline still removes locally stored history.
      }
    }
    await _writeCache(const <CallRecord>[]);
  }
}
