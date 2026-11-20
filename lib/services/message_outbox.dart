import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_message.dart';

/// Durable local queue for messages that could not reach Supabase.
class MessageOutbox {
  MessageOutbox._();

  static const _storageKey = 'bro.message_outbox.v1';
  static final _items = <String, PendingMessage>{};
  static final revision = ValueNotifier<int>(0);
  static bool _loaded = false;
  static final _flushingSenders = <String>{};

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    if (_loaded) return;
    const storage = FlutterSecureStorage();
    final old = prefs.getString(_storageKey);
    var raw = await storage.read(key: _storageKey);
    if (old != null) {
      if (raw == null) {
        await storage.write(key: _storageKey, value: old);
        raw = old;
      }
      await prefs.remove(_storageKey);
    }
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final value in decoded) {
            if (value is! Map) continue;
            try {
              final item =
                  PendingMessage.fromJson(Map<String, dynamic>.from(value));
              // A process restart cannot leave a send actively in flight.
              if (item.status == 'sending') item.status = 'queued';
              _items[item.localId] = item;
            } catch (_) {
              // Ignore malformed stale queue entries.
            }
          }
        }
      } catch (_) {
        // Ignore a malformed preference and start with an empty queue.
      }
    }
    _loaded = true;
    _notify();
  }

  static List<PendingMessage> _forSender(String senderId) =>
      _items.values.where((item) => item.senderId == senderId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  static List<PendingMessage> forConversation(
    String conversationId, {
    required String senderId,
  }) =>
      _forSender(senderId)
          .where((item) => item.conversationId == conversationId)
          .toList(growable: false);

  static Future<void> put(PendingMessage item) async {
    await load();
    _items[item.localId] = item;
    await _persist();
    _notify();
  }

  static Future<void> remove(String localId) async {
    await load();
    if (_items.remove(localId) == null) return;
    await _persist();
    _notify();
  }

  static Future<void> update(PendingMessage item) async {
    await load();
    if (!_items.containsKey(item.localId)) return;
    _items[item.localId] = item;
    await _persist();
    _notify();
  }

  /// Flush this account's queued and failed messages while it remains active.
  /// The send callback must throw when delivery fails.
  static Future<void> flush(
    Future<void> Function(PendingMessage item) send, {
    required String senderId,
    required bool Function() isSenderActive,
  }) async {
    await load();
    if (!_flushingSenders.add(senderId)) return;
    try {
      for (final item in _forSender(senderId)) {
        if (!isSenderActive()) break;
        if (item.status != 'queued' && item.status != 'failed') continue;
        if (item.expiresAt != null &&
            item.expiresAt!.isBefore(DateTime.now())) {
          await remove(item.localId);
          continue;
        }
        item.status = 'sending';
        await update(item);
        if (!isSenderActive()) {
          item.status = 'queued';
          await update(item);
          break;
        }
        try {
          await send(item);
          await remove(item.localId);
        } catch (_) {
          item.status = 'failed';
          item.retryCount += 1;
          await update(item);
        }
      }
    } finally {
      _flushingSenders.remove(senderId);
    }
  }

  static Future<void> _persist() async {
    await const FlutterSecureStorage().write(
        key: _storageKey,
        value: jsonEncode(_items.values.map((e) => e.toJson()).toList()));
  }

  static void _notify() => revision.value++;
}
