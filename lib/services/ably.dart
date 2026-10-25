import 'dart:async';
import 'package:ably_flutter/ably_flutter.dart' as ably;
import '../models/profile.dart';

/// Ably-backed realtime transport for NYX.
///
/// Replaces the Supabase Realtime layer. Each 1:1 conversation maps to an
/// Ably channel named `chat:<conversationId>`. Messages, typing indicators and
/// presence all travel over that channel.
///
/// Authentication: the Ably API key is supplied at init time (from the
/// `ABLY_KEY` build define). It is NOT hard-coded here so it never lands in
/// source control. For a real release this should be swapped for token auth
/// via [ClientOptions.authUrl] / [ClientOptions.authCallback].
class AblyService {
  AblyService._();
  static final AblyService instance = AblyService._();

  ably.Realtime? _realtime;

  /// Per-conversation live message streams.
  final Map<String, StreamController<List<Message>>> _messageStreams = {};
  final Map<String, StreamSubscription<ably.Message>> _messageSubs = {};
  final Map<String, List<Message>> _messageBuffers = {};

  /// Per-conversation typing broadcast streams: (clientId, isTyping).
  final Map<String, StreamController<TypingEvent>> _typingStreams = {};
  final Map<String, StreamSubscription<ably.Message>> _typingSubs = {};

  /// Per-conversation presence streams: list of online clientIds.
  final Map<String, StreamController<List<String>>> _presenceStreams = {};
  final Map<String, StreamSubscription<ably.PresenceMessage>> _presenceSubs = {};
  final Map<String, Set<String>> _presenceSets = {};

  static const _messageName = 'message';
  static const _typingName = 'typing';

  bool get isInitialized => _realtime != null;
  ably.ConnectionState get connectionState =>
      _realtime?.connection.state ?? ably.ConnectionState.initialized;
  String? get clientId => _realtime?.options.clientId;

  /// Initialise the Ably Realtime connection. [key] is the Ably API key (or a
  /// token); [clientId] identifies this user for presence.
  Future<void> init(String key, {required String clientId}) async {
    if (_realtime != null) return;
    _realtime = ably.Realtime(
      options: ably.ClientOptions(key: key, clientId: clientId),
    );
    await _realtime!.connect();
  }

  ably.RealtimeChannel _channel(String conversationId) =>
      _realtime!.channels.get('chat:$conversationId');

  // ---- Messages ---------------------------------------------------------

  /// Live stream of the full message list for a conversation. Seeds from Ably
  /// channel history on first subscription, then appends live messages.
  Stream<List<Message>> watchMessages(String conversationId) {
    final controller = _messageStreams.putIfAbsent(
      conversationId,
      () => StreamController<List<Message>>.broadcast(),
    );
    _ensureMessageStream(conversationId);
    return controller.stream;
  }

  Future<void> _ensureMessageStream(String conversationId) async {
    if (_messageSubs.containsKey(conversationId)) return;
    final channel = _channel(conversationId);
    final buffer = _messageBuffers.putIfAbsent(conversationId, () => []);
    final controller = _messageStreams[conversationId]!;

    // Seed from history (most recent page first), then reverse to chronological.
    try {
      final history = await channel.history();
      final seeded = <Message>[];
      var page = history;
      var pages = 0;
      while (pages < 5) {
        for (final raw in page.items) {
          if (raw.name == _messageName) {
            final parsed = _parseMessage(raw);
            if (parsed != null) seeded.add(parsed);
          }
        }
        if (!page.hasNext()) break;
        page = await page.next();
        pages++;
      }
      seeded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      buffer
        ..clear()
        ..addAll(seeded);
    } catch (_) {
      // No history available yet — start empty and rely on live messages.
    }
    if (controller.hasListener) controller.add(List.of(buffer));

    final sub = channel.subscribe(name: _messageName).listen((raw) {
      final parsed = _parseMessage(raw);
      if (parsed == null) return;
      buffer.add(parsed);
      if (controller.hasListener) controller.add(List.of(buffer));
    });
    _messageSubs[conversationId] = sub;
  }

  /// Send a chat message over the conversation channel.
  Future<void> sendMessage(String conversationId, Message msg) async {
    final data = {
      'id': msg.id,
      'conversation_id': msg.conversationId,
      'sender_id': msg.senderId,
      'content': msg.content,
      'created_at': msg.createdAt.toIso8601String(),
    };
    await _channel(conversationId).publish(
      name: _messageName,
      data: data,
    );
  }

  // ---- Typing -----------------------------------------------------------

  /// Broadcast that this user is (or is not) typing.
  Future<void> broadcastTyping(String conversationId, bool isTyping) async {
    await _channel(conversationId).publish(
      name: _typingName,
      data: {'typing': isTyping, 'clientId': clientId},
    );
  }

  /// Stream of typing events from the peer(s) in a conversation.
  Stream<TypingEvent> watchTyping(String conversationId) {
    final controller = _typingStreams.putIfAbsent(
      conversationId,
      () => StreamController<TypingEvent>.broadcast(),
    );
    if (!_typingSubs.containsKey(conversationId)) {
      final channel = _channel(conversationId);
      final sub = channel.subscribe(name: _typingName).listen((raw) {
        final d = raw.data is Map
            ? Map<String, dynamic>.from(raw.data as Map)
            : <String, dynamic>{};
        final who = d['clientId'] as String? ?? raw.clientId;
        final typing = d['typing'] as bool? ?? false;
        if (who != null && who != clientId) {
          controller.add(TypingEvent(userId: who, isTyping: typing));
        }
      });
      _typingSubs[conversationId] = sub;
    }
    return controller.stream;
  }

  // ---- Presence ---------------------------------------------------------

  /// Mark this user present on a conversation channel with display metadata.
  Future<void> enterPresence(String conversationId, Profile profile) async {
    await _channel(conversationId).presence.enter({
      'username': profile.username,
      'display_name': profile.displayName ?? profile.username,
    });
  }

  Future<void> leavePresence(String conversationId) async {
    await _channel(conversationId).presence.leave();
  }

  /// Live list of online clientIds for a conversation.
  Stream<List<String>> watchPresence(String conversationId) {
    final controller = _presenceStreams.putIfAbsent(
      conversationId,
      () => StreamController<List<String>>.broadcast(),
    );
    if (!_presenceSubs.containsKey(conversationId)) {
      final channel = _channel(conversationId);
      final set = _presenceSets.putIfAbsent(conversationId, () => {});
      void emit() {
        if (controller.hasListener) controller.add(set.toList());
      }
      final sub = channel
          .presence
          .subscribe(actions: [ably.PresenceAction.enter, ably.PresenceAction.leave])
          .listen((pm) {
        final who = pm.clientId;
        if (who == null) return;
        if (pm.action == ably.PresenceAction.enter || pm.action == ably.PresenceAction.update) {
          set.add(who);
        } else {
          set.remove(who);
        }
        emit();
      });
      _presenceSubs[conversationId] = sub;
      // Snapshot current members.
      channel.presence.get().then((members) {
        for (final m in members) {
          if (m.clientId != null) set.add(m.clientId!);
        }
        emit();
      }).catchError((_) {});
    }
    return controller.stream;
  }

  // ---- Lifecycle --------------------------------------------------------

  Future<void> disposeConversation(String conversationId) async {
    await _messageSubs[conversationId]?.cancel();
    await _typingSubs[conversationId]?.cancel();
    await _presenceSubs[conversationId]?.cancel();
    _messageSubs.remove(conversationId);
    _typingSubs.remove(conversationId);
    _presenceSubs.remove(conversationId);
    await _messageStreams[conversationId]?.close();
    await _typingStreams[conversationId]?.close();
    await _presenceStreams[conversationId]?.close();
    _messageStreams.remove(conversationId);
    _typingStreams.remove(conversationId);
    _presenceStreams.remove(conversationId);
    _messageBuffers.remove(conversationId);
    _presenceSets.remove(conversationId);
  }

  Future<void> close() async {
    for (final id in _messageSubs.keys.toList()) {
      await disposeConversation(id);
    }
    await _realtime?.close();
    _realtime = null;
  }
}

class TypingEvent {
  final String userId;
  final bool isTyping;
  TypingEvent({required this.userId, required this.isTyping});
}

extension MessageAbly on Message {}

/// Parse an Ably wire message into the app [Message] model. Returns null if
/// the payload is missing required fields.
Message? _parseMessage(ably.Message raw) {
  final d = raw.data is Map
      ? Map<String, dynamic>.from(raw.data as Map)
      : <String, dynamic>{};
  final id = (d['id'] ?? raw.id) as String?;
  final senderId = d['sender_id'] as String? ?? raw.clientId;
  final content = d['content'] as String?;
  final createdAt = d['created_at'] != null
      ? DateTime.tryParse(d['created_at'] as String) ?? DateTime.now()
      : DateTime.now();
  if (id == null || senderId == null || content == null) return null;
  return Message(
    id: id,
    conversationId: (d['conversation_id'] as String?) ?? '',
    senderId: senderId,
    content: content,
    createdAt: createdAt,
  );
}
