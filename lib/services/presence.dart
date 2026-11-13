import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared last-seen cache so chat list, chat header, and profile agree.
///
/// `record_last_seen` used to run only when the app resumed, so anyone sitting
/// in BRO looked offline after two minutes. We heartbeat while foregrounded
/// and treat a peer as online for [onlineFor] after their last ping.
class Presence {
  Presence._();

  static const onlineFor = Duration(seconds: 45);

  static final epoch = ValueNotifier<int>(0);

  static Timer? _heartbeat;
  static Timer? _poll;
  static bool _foreground = true;
  static Set<String> _listPeers = {};
  static final Set<String> _focus = {};
  static final Map<String, DateTime?> _lastSeen = {};
  static final Set<String> _hidden = {};

  static Set<String> get _watched => {..._listPeers, ..._focus};

  static void bind() {
    _foreground = true;
    startHeartbeat();
  }

  static void unbind() {
    _heartbeat?.cancel();
    _poll?.cancel();
    _heartbeat = null;
    _poll = null;
    _listPeers = {};
    _focus.clear();
    _lastSeen.clear();
    _hidden.clear();
  }

  static void resume() {
    _foreground = true;
    startHeartbeat();
    unawaited(refresh());
  }

  static void pause() {
    _foreground = false;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  static Future<void> _ping() async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;
    try {
      await client.rpc('record_last_seen');
    } catch (_) {}
  }

  static void startHeartbeat() {
    if (Supabase.instance.client.auth.currentUser == null) return;
    unawaited(_ping());
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_foreground) unawaited(_ping());
    });
  }

  static void setListPeers(Iterable<String?> ids) {
    final next = ids.whereType<String>().where((id) => id.isNotEmpty).toSet();
    if (setEquals(next, _listPeers)) {
      _ensurePoll();
      return;
    }
    _listPeers = next;
    _ensurePoll();
    unawaited(refresh());
  }

  static void focus(String? id) {
    if (id == null || id.isEmpty) return;
    if (_focus.add(id)) {
      _ensurePoll();
      unawaited(refresh());
    }
  }

  static void unfocus(String? id) {
    if (id == null) return;
    _focus.remove(id);
    _ensurePoll();
  }

  static bool isOnline(String? userId) {
    if (userId == null || _hidden.contains(userId)) return false;
    final at = _lastSeen[userId];
    if (at == null) return false;
    return DateTime.now().difference(at) < onlineFor;
  }

  static String? label(String? userId) {
    if (userId == null || _hidden.contains(userId)) return null;
    final at = _lastSeen[userId];
    if (at == null) return null;
    return formatPresenceLabel(at, onlineFor: onlineFor);
  }

  static Future<void> refresh() async {
    final ids = _watched.toList();
    if (ids.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('visible_profiles')
          .select('id,last_seen_at,status_visibility')
          .filter('id', 'in', ids);
      _hidden.removeWhere((id) => ids.contains(id));
      for (final row in rows as List) {
        final id = row['id'] as String;
        final vis = row['status_visibility'] as String? ?? 'everyone';
        if (vis == 'nobody') {
          _hidden.add(id);
          _lastSeen[id] = null;
          continue;
        }
        final raw = row['last_seen_at'] as String?;
        _lastSeen[id] =
            raw == null ? null : DateTime.parse(raw).toLocal();
      }
      epoch.value++;
    } catch (_) {}
  }

  static void _ensurePoll() {
    if (_watched.isEmpty) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(
        const Duration(seconds: 12), (_) => unawaited(refresh()));
  }
}

/// Human-readable last-seen line. 'online' if [lastSeen] is within [onlineFor].
String formatPresenceLabel(
  DateTime lastSeen, {
  DateTime? now,
  Duration onlineFor = Presence.onlineFor,
}) {
  final diff = (now ?? DateTime.now()).difference(lastSeen);
  if (diff < onlineFor) return 'online';
  if (diff.inMinutes < 1) return 'last seen just now';
  if (diff.inMinutes < 60) return 'last seen ${diff.inMinutes}m ago';
  final local = lastSeen.toLocal();
  final clock = now ?? DateTime.now();
  if (diff.inHours < 24 && local.day == clock.day) {
    final h = local.hour == 0
        ? 12
        : (local.hour > 12 ? local.hour - 12 : local.hour);
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour >= 12 ? 'PM' : 'AM';
    return 'last seen today at $h:$m $ap';
  }
  if (diff.inDays == 1 ||
      (clock.day - local.day == 1 && clock.difference(local).inHours < 36)) {
    return 'last seen yesterday';
  }
  if (diff.inDays < 7) return 'last seen ${diff.inDays} days ago';
  return 'last seen ${local.day}/${local.month}/${local.year}';
}
