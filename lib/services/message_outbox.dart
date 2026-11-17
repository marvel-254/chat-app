import 'dart:convert';

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
  static bool _flushing = false;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
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

  static List<PendingMessage> get all =>
      List.unmodifiable(_items.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  static List<PendingMessage> forConversation(String conversationId) => all
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

  /// Flush queued and failed messages. The callback is responsible for the
  /// actual network send and must throw when delivery fails.
  static Future<void> flush(
      Future<void> Function(PendingMessage item) send) async {
    await load();
    if (_flushing) return;
    _flushing = true;
    try {
      for (final item in all) {
        if (item.status != 'queued' && item.status != 'failed') continue;
        if (item.expiresAt != null &&
            item.expiresAt!.isBefore(DateTime.now())) {
          await remove(item.localId);
          continue;
        }
        item.status = 'sending';
        await update(item);
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
      _flushing = false;
    }
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, jsonEncode(_items.values.map((e) => e.toJson()).toList()));
  }

  static void _notify() => revision.value++;
}
