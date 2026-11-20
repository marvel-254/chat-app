import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  ) async =>
      _record(
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

  static Future<CallRecord> advance(String id, String action) async => _record(
        await Supa.client.rpc('advance_bro_call',
            params: {'p_id': id, 'p_action': action}).timeout(timeout),
      );

  static Future<CallRecord?> incoming(String owner) async {
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
  }

  static Future<CallRecord?> get(String id) async {
    final row = await Supa.client
        .from('call_sessions')
        .select()
        .eq('id', id)
        .maybeSingle()
        .timeout(timeout);
    return row == null ? null : _record(row);
  }

  static String _key(String owner) => 'recent_calls_v1_$owner';
  static Future<List<CallRecord>> cached(String owner) async {
    try {
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
    } catch (_) {
      return [];
    }
  }

  static Future<List<CallRecord>> recent(String owner) async {
    _requireOwner(owner);
    final rows = await Supa.client
        .from('call_sessions')
        .select()
        .or('caller_id.eq.$owner,callee_id.eq.$owner')
        .not('ended_at', 'is', null)
        .order('started_at', ascending: false)
        .order('id')
        .limit(100)
        .timeout(timeout);
    _requireOwner(owner);
    return rows.map(_record).toList();
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
    } catch (_) {
      // Storage may be unavailable in restricted browsing contexts.
    }
  }

  static void _requireOwner(String owner) {
    if (Supa.currentUser?.id != owner) throw StateError('Account changed');
  }

  static CallRecord _record(dynamic row) =>
      CallRecord(Map<String, dynamic>.from(row as Map));
}
