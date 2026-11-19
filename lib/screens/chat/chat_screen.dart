import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../services/supabase.dart';
import '../../services/presence.dart';
import '../../services/connection_monitor.dart';
import '../../services/message_outbox.dart';
import '../../services/voice_note.dart';
import '../../services/scheduled_messages.dart' as scheduled;
import '../../services/secure_screen.dart';
import '../../models/profile.dart';
import '../../models/pending_message.dart';
import '../../ui/states.dart';
import '../../ui/errors.dart';
import '../../ui/motion.dart';
import '../../widgets/game_presence.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Presence;
import 'widgets/avatar.dart';
import '../navigation/nav_sidebar.dart';
import '../lock_gate.dart';
import '../../services/app_lock.dart';

const _adaptiveBreakpoint = app_colors.adaptiveBreakpoint;

class _P {
  static const bg = app_colors.bg;
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const surfaceLow = app_colors.surfaceLow;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const success = app_colors.success;
  static const primary = app_colors.volt;
  static const volt = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
}

BoxDecoration _chatCanvas(String name, {String? imageUrl}) =>
    app_colors.chatCanvas(name, imageUrl: imageUrl);

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final Profile? initialPeer;
  const ChatScreen({super.key, required this.conversationId, this.initialPeer});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _selfTyping = false;
  DateTime? _lastTypingPulse;
  bool _sendingMessage = false;
  Timer? _typingTimer;
  late Profile? _peer = widget.initialPeer;
  bool _conversationLocked = false;
  bool _conversationUnlocked = false;
  bool _lockReady = false;
  String? _peerTyping;
  Timer? _peerTypingTimer;
  RealtimeChannel? _callChannel;
  bool _incomingPrompt = false;
  String _chatBackground = 'default';
  String? _chatBackgroundImageUrl;
  Duration? _messageExpiry;
  bool _pinnedBannerDismissed = false;
  int _pinnedBannerIndex = 0;
  Message? _replyTo;
  final _pendingMessages = <String, PendingMessage>{}; // keyed by localId
  Timer? _draftSaveTimer;
  int _lastMarkedMessageCount = 0;
  String? _lastMarkedMessageId;
  bool _showJumpToBottom = false;
  late final VoidCallback _chatBackgroundListener = () => _loadChatBackground();
  late final VoidCallback _outboxConnectivityListener = _onConnectivityChanged;
  StreamSubscription<AuthState>? _outboxAuthSubscription;
  String? _outboxSenderId;

  void _onOutboxAuthChanged(AuthState _) {
    final senderId = Supa.currentUser?.id;
    if (!mounted || _outboxSenderId == senderId) return;
    setState(() {
      _outboxSenderId = senderId;
      _pendingMessages.clear();
    });
    unawaited(_restorePendingMessages());
  }

  void _onConnectivityChanged() {
    if (ConnectionMonitor.isOnline.value) unawaited(_flushOutbox());
  }

  List<PendingMessage> _outboxFor(String senderId) =>
      MessageOutbox.forConversation(widget.conversationId, senderId: senderId);

  Future<void> _restorePendingMessages() async {
    final senderId = Supa.currentUser?.id;
    if (senderId == null) return;
    await MessageOutbox.load();
    if (!mounted || Supa.currentUser?.id != senderId) return;
    final restored = _outboxFor(senderId);
    if (restored.isEmpty) return;
    setState(() {
      for (final item in restored) {
        _pendingMessages[item.localId] = item;
      }
    });
    if (ConnectionMonitor.isOnline.value) unawaited(_flushOutbox());
  }

  Future<void> _flushOutbox() async {
    final senderId = Supa.currentUser?.id;
    if (senderId == null || !ConnectionMonitor.isOnline.value) return;
    bool isSenderActive() => Supa.currentUser?.id == senderId;
    await MessageOutbox.flush(
      (item) async {
        await Supa.sendMessage(
          item.conversationId,
          item.content,
          expiry: item.expiresAt?.difference(DateTime.now()),
          replyToId: item.replyToId,
          expectedSenderId: item.senderId,
        );
        if (mounted &&
            isSenderActive() &&
            item.conversationId == widget.conversationId) {
          setState(() => _pendingMessages.remove(item.localId));
          _rollToBottom();
        }
        if (isSenderActive()) Supa.triggerConversationRefresh();
      },
      senderId: senderId,
      isSenderActive: isSenderActive,
    );
    if (!mounted || !isSenderActive()) return;
    final remaining = _outboxFor(senderId);
    setState(() {
      _pendingMessages
        ..clear()
        ..addEntries(remaining.map((item) => MapEntry(item.localId, item)));
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final current = _scroll.offset;
    final shouldShow = (max - current) > 350;
    if (shouldShow != _showJumpToBottom && mounted) {
      setState(() => _showJumpToBottom = shouldShow);
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  String _expiryLabel(Duration value) => switch (value.inDays) {
        1 => '24 hours',
        7 => '7 days',
        30 => '30 days',
        _ => '${value.inDays} days',
      };

  @override
  void initState() {
    super.initState();
    Presence.focus(widget.initialPeer?.id);
    _loadPeer();
    _loadChatBackground();
    _loadMessageExpiry();
    _loadDraft();
    Supa.onTyping(widget.conversationId, _onPeerTyping);
    _listenForCalls();
    _checkConversationLock();
    _ctrl.addListener(_onDraftChanged);
    _scroll.addListener(_onScroll);
    ConnectionMonitor.isOnline.addListener(_outboxConnectivityListener);
    _outboxSenderId = Supa.currentUser?.id;
    _outboxAuthSubscription =
        Supa.authStateChanges.listen(_onOutboxAuthChanged);
    unawaited(_restorePendingMessages());
    Supa.chatBackgroundChanged.addListener(_chatBackgroundListener);
  }

  Future<void> _loadDraft() async {
    try {
      final draft = await Supa.loadDraft(widget.conversationId);
      if (mounted && draft != null && draft.isNotEmpty) {
        _ctrl.text = draft;
      }
    } catch (_) {}
  }

  void _onDraftChanged() {
    _draftSaveTimer?.cancel();
    final text = _ctrl.text;
    if (text.isEmpty) {
      // Clear draft when text is empty
      unawaited(Supa.saveDraft(widget.conversationId, ''));
      return;
    }
    _draftSaveTimer = Timer(const Duration(seconds: 1), () {
      Supa.saveDraft(widget.conversationId, text).catchError((_) {});
    });
  }

  Future<void> _checkConversationLock() async {
    try {
      final isLocked = await Supa.isConversationLocked(widget.conversationId);
      if (mounted) {
        setState(() {
          _conversationLocked = isLocked;
          _lockReady = true;
        });
        // Prevent screenshots for all conversations (issue #81).
        // Locked conversations already enabled this; now we apply it broadly.
        await SecureScreen.enable();
      }
    } catch (_) {
      if (mounted) setState(() => _lockReady = true);
    }
  }

  Future<void> _loadMessageExpiry() async {
    try {
      final expiry = await Supa.getMessageExpiry(widget.conversationId);
      if (mounted) setState(() => _messageExpiry = expiry);
    } catch (_) {}
  }

  Future<void> _chooseMessageExpiry() async {
    const choices = <String, Duration?>{
      'Off': Duration.zero,
      '24 hours': Duration(hours: 24),
      '7 days': Duration(days: 7),
      '30 days': Duration(days: 30),
    };
    final selected = await showModalBottomSheet<Duration?>(
      context: context,
      backgroundColor: _P.surface,
      builder: (sheetContext) => SafeArea(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Disappearing messages')),
          for (final entry in choices.entries)
            ListTile(
                title: Text(entry.key),
                onTap: () => Navigator.pop(sheetContext, entry.value)),
          const SizedBox(height: 8),
        ],
      )),
    );
    if (selected == null) return;
    try {
      await Supa.setMessageExpiry(widget.conversationId, selected);
      if (mounted) {
        setState(
            () => _messageExpiry = selected == Duration.zero ? null : selected);
      }
    } catch (_) {
      _unsupported("We couldn't update the disappearing-message timer.");
    }
  }

  Future<bool> _confirmIdentity(String reason) async {
    final ok = await AppLock.authenticate(reason: reason);
    if (ok) return true;
    if (!mounted) return false;
    var passed = false;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LockGate(
        title: reason,
        reason: reason,
        onUnlocked: () {
          passed = true;
          Navigator.of(context).pop();
        },
      ),
    ));
    return passed;
  }

  Future<void> _lockConversation() async {
    if (!await _confirmIdentity('Lock this conversation')) return;
    try {
      await Supa.setConversationLocked(widget.conversationId, true);
      if (!mounted) return;
      setState(() {
        _conversationLocked = true;
        _conversationUnlocked = false;
      });
      await SecureScreen.enable();
      _unsupported('This chat is locked on this device.');
    } catch (e) {
      _unsupported(friendlyErrorMessage(e,
          fallback: "We couldn't lock this chat. Try again?"));
    }
  }

  Future<void> _unlockConversation() async {
    if (!await _confirmIdentity('Unlock this conversation')) return;
    try {
      await Supa.setConversationLocked(widget.conversationId, false);
      if (!mounted) return;
      setState(() {
        _conversationLocked = false;
        _conversationUnlocked = true;
      });
      await SecureScreen.disable();
      _unsupported('Chat unlocked.');
    } catch (e) {
      _unsupported(friendlyErrorMessage(e,
          fallback: "We couldn't unlock this chat. Try again?"));
    }
  }

  Future<void> _loadChatBackground() async {
    try {
      final profile = await Supa.getProfile(Supa.currentUser!.id);
      if (profile == null) return;
      final imagePath = profile.chatBackgroundImagePath;
      String? imageUrl;
      if (profile.chatBackground == 'custom' && imagePath != null) {
        imageUrl = await Supa.chatBackgroundUrl(imagePath);
      }
      if (mounted) {
        setState(() {
          _chatBackground = profile.chatBackground;
          _chatBackgroundImageUrl = imageUrl;
        });
      }
    } catch (e) {
      debugPrint('Failed to load chat background: $e');
    }
  }

  void _listenForCalls() {
    final channel = Supa.client.channel('call:${widget.conversationId}',
        opts: const RealtimeChannelConfig(private: true));
    _callChannel = channel;
    channel
        .onBroadcast(
            event: 'signal',
            callback: (payload) {
              if (payload['to'] != Supa.currentUser?.id ||
                  payload['kind'] != 'invite' ||
                  _incomingPrompt) {
                return;
              }
              final callId = payload['call_id'] as String?;
              if (callId != null) {
                _showIncomingCall(callId, payload['data'] as Map?,
                    payload['from'] as String?);
              }
            })
        .subscribe();
  }

  Future<void> _showIncomingCall(
      String callId, Map? details, String? callerId) async {
    final peer =
        _peer ?? (callerId == null ? null : await Supa.getProfile(callerId));
    if (peer == null || !mounted) return;
    _incomingPrompt = true;
    final video = details?['video'] == true;
    final answer = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
              backgroundColor: _P.surface,
              title: Text(video ? 'Incoming video call' : 'Incoming voice call',
                  style: const TextStyle(color: _P.text)),
              content: Text('${peer.label} (@${peer.username}) is calling.',
                  style: const TextStyle(color: _P.muted)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Decline')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Answer')),
              ],
            ));
    _incomingPrompt = false;
    if (!mounted) return;
    if (answer == true) {
      context.push(
          '/call/${widget.conversationId}?id=$callId&video=$video&outgoing=false',
          extra: peer);
    } else {
      await _callChannel?.httpSend(event: 'signal', payload: {
        'call_id': callId,
        'from': Supa.currentUser!.id,
        'to': peer.id,
        'kind': 'hangup',
        'data': const {},
      });
    }
  }

  void _startCall({required bool video}) {
    final peer = _peer;
    if (peer == null) {
      _unsupported(
          'The other person’s profile is still loading. Try again in a moment.');
      return;
    }
    final callId = const Uuid().v4();
    context.push(
        '/call/${widget.conversationId}?id=$callId&video=$video&outgoing=true',
        extra: peer);
  }

  void _onPeerTyping(String userId, bool isTyping) {
    final currentUserId = Supa.currentUser?.id;
    if (!mounted || currentUserId == null || userId == currentUserId) return;
    if (isTyping) {
      setState(() => _peerTyping = userId);
      _peerTypingTimer?.cancel();
      _peerTypingTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _peerTyping = null);
      });
    } else {
      _peerTypingTimer?.cancel();
      if (mounted && _peerTyping == userId) setState(() => _peerTyping = null);
    }
  }

  Future<void> _loadPeer() async {
    try {
      final ids = await Supa.client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', widget.conversationId)
          .not('user_id', 'eq', Supa.currentUser!.id)
          .limit(1);
      if (!mounted) return;
      final uid = (ids as List)
          .cast<Map<String, dynamic>>()
          .firstOrNull?['user_id'] as String?;
      if (uid == null) return;
      Presence.focus(uid);
      final profile = await Supa.getProfile(uid);
      if (mounted) {
        setState(() => _peer = profile ?? _peer);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onDraftChanged);
    unawaited(SecureScreen.disable());
    Supa.unsubscribeTyping(widget.conversationId);
    Presence.unfocus(_peer?.id ?? widget.initialPeer?.id);
    _ctrl.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    _draftSaveTimer?.cancel();
    ConnectionMonitor.isOnline.removeListener(_outboxConnectivityListener);
    unawaited(_outboxAuthSubscription?.cancel());
    Supa.chatBackgroundChanged.removeListener(_chatBackgroundListener);
    final callChannel = _callChannel;
    if (callChannel != null) Supa.client.removeChannel(callChannel);
    super.dispose();
  }

  Future<void> _openVoiceNote() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _VoiceNoteDialog(conversationId: widget.conversationId),
    );
    if (result != null && result.isNotEmpty) {
      // The dialog already played a short confirmation; nothing further needed.
    }
  }

  Future<void> _send() async {
    final draft = _ctrl.text;
    final content = draft.trim();
    final senderId = Supa.currentUser?.id;
    if (senderId == null || content.isEmpty || _sendingMessage) return;

    setState(() => _sendingMessage = true);
    _typingTimer?.cancel();
    _selfTyping = false;
    unawaited(Supa.broadcastTyping(widget.conversationId, false));
    final replyToId = _replyTo?.id;
    final localId = const Uuid().v4();
    final expiresAt =
        _messageExpiry == null ? null : DateTime.now().add(_messageExpiry!);
    final pending = PendingMessage(
      localId: localId,
      conversationId: widget.conversationId,
      senderId: senderId,
      content: content,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      replyToId: replyToId,
    );
    try {
      await _addPending(pending);
      await Supa.sendMessage(
        widget.conversationId,
        content,
        expiry: _messageExpiry,
        replyToId: replyToId,
        expectedSenderId: senderId,
      );
      _removePending(localId);
      if (Supa.currentUser?.id != senderId) return;
      // Trigger chat list refresh so the sender sees the updated preview
      Supa.triggerConversationRefresh();
      if (!mounted) return;
      if (_ctrl.text == draft) _ctrl.clear();
      setState(() => _replyTo = null);
      unawaited(Supa.saveDraft(widget.conversationId, ''));
      _rollToBottom();
    } catch (e) {
      _markPendingFailed(pending);
      if (mounted && Supa.currentUser?.id == senderId) {
        _unsupported(friendlyErrorMessage(e,
            fallback:
                "That message didn't go through. It's still in the box if you want to retry."));
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  /// Pending (optimistic) messages keyed by their local id. These are the
  /// messages sent before the server echoed them back, rendered as a pending
  /// bubble until they reach the server.
  Future<void> _addPending(PendingMessage pm) async {
    _pendingMessages[pm.localId] = pm;
    await MessageOutbox.put(pm);
  }

  void _removePending(String localId) {
    _pendingMessages.remove(localId);
    unawaited(MessageOutbox.remove(localId));
  }

  void _markPendingFailed(PendingMessage item) {
    if (item.status == 'sent') return;
    item.status = 'failed';
    item.retryCount += 1;
    unawaited(MessageOutbox.update(item));
    if (mounted && Supa.currentUser?.id == item.senderId) setState(() {});
  }

  /// The messages the UI should render: server rows merged with in-flight
  /// pending rows, deduplicated and sorted oldest-to-newest.
  List<Message> _displayMessages(List<Message> serverMessages) {
    final senderId = Supa.currentUser?.id;
    final pending = _pendingMessages.values
        .where((pm) =>
            pm.senderId == senderId &&
            (pm.status == 'sending' || pm.status == 'failed'))
        .toList();
    final byId = <String, Message>{};
    for (final m in serverMessages) {
      if (!byId.containsKey(m.id)) byId[m.id] = m;
    }
    for (final pm in pending) {
      byId[pm.localId] = pm.toOptimisticMessage();
    }
    final merged = <Message>[];
    final seen = <String>{};
    for (final m in byId.values) {
      if (seen.add(m.id)) merged.add(m);
    }
    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  /// Mark unread messages as read. Called once when the chat opens and again
  /// when new messages arrive (detected by comparing the message count/id).
  void _markUnreadAsReadIfNeeded(List<Message> messages) {
    if (messages.isEmpty) return;
    // Only mark if the message list changed since the last time we marked read.
    // This avoids calling the RPC on every rebuild.
    final lastId = messages.last.id;
    if (messages.length == _lastMarkedMessageCount &&
        lastId == _lastMarkedMessageId) {
      return;
    }
    // Check if there are any unread inbound messages
    final hasUnread = messages
        .any((m) => m.senderId != Supa.currentUser!.id && m.readAt == null);
    if (!hasUnread) return;
    _lastMarkedMessageCount = messages.length;
    _lastMarkedMessageId = lastId;
    // The RPC marks all unread messages in the conversation at once.
    unawaited(Supa.markRead(widget.conversationId));
  }

  void _onTypingChanged(String text) {
    if (text.trim().isEmpty) {
      _typingTimer?.cancel();
      if (_selfTyping) {
        _selfTyping = false;
        unawaited(Supa.broadcastTyping(widget.conversationId, false));
      }
      return;
    }
    final now = DateTime.now();
    final pulse = !_selfTyping ||
        _lastTypingPulse == null ||
        now.difference(_lastTypingPulse!) >= const Duration(milliseconds: 1500);
    if (pulse) {
      _selfTyping = true;
      _lastTypingPulse = now;
      unawaited(Supa.broadcastTyping(widget.conversationId, true));
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _selfTyping = false;
      unawaited(Supa.broadcastTyping(widget.conversationId, false));
    });
  }

  void _rollToBottom() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  /// Scroll to roughly the position of [messageIndex] out of [totalMessages].
  void _scrollToMessage(int messageIndex, int totalMessages) {
    if (!_scroll.hasClients || totalMessages == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final target =
          (messageIndex / (totalMessages - 1).clamp(1, 999999)) * max;
      _scroll.animateTo(target.clamp(0.0, max),
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    });
  }

  void _onRetry() => setState(() {});

  void _unsupported(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showOutbox() async {
    final senderId = Supa.currentUser?.id;
    if (senderId == null) return;
    await MessageOutbox.load();
    if (!mounted || Supa.currentUser?.id != senderId) return;
    final items = _outboxFor(senderId)
        .where((item) => item.status == 'failed' || item.status == 'queued')
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _P.surface,
      builder: (sheetContext) => StreamBuilder<AuthState>(
        stream: Supa.authStateChanges,
        builder: (context, _) {
          if (Supa.currentUser?.id != senderId) return const SizedBox.shrink();
          return _buildOutboxSheet(sheetContext, items, senderId);
        },
      ),
    );
  }

  Widget _buildOutboxSheet(
    BuildContext sheetContext,
    List<PendingMessage> items,
    String senderId,
  ) =>
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: items.isEmpty
              ? const SizedBox(
                  height: 80,
                  child: Center(child: Text('No messages waiting to send.')),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Message outbox',
                        style: TextStyle(
                            color: _P.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    for (final item in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.status == 'failed'
                              ? Icons.error_outline
                              : Icons.schedule_send_outlined,
                          color: item.status == 'failed'
                              ? Colors.orangeAccent
                              : _P.primary,
                        ),
                        title: Text(item.content,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(item.status == 'failed'
                            ? 'Waiting for retry'
                            : 'Waiting for connection'),
                        trailing: IconButton(
                          tooltip: 'Retry now',
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            if (Supa.currentUser?.id != senderId) return;
                            item.status = 'queued';
                            await MessageOutbox.update(item);
                            if (mounted && Supa.currentUser?.id == senderId) {
                              setState(
                                  () => _pendingMessages[item.localId] = item);
                            }
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (Supa.currentUser?.id == senderId) {
                              await _flushOutbox();
                            }
                          },
                        ),
                      ),
                  ],
                ),
        ),
      );

  void _showChatMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingMessages.values.any(
                (item) => item.status == 'failed' || item.status == 'queued'))
              _MenuTile(
                icon: Icons.outbox_outlined,
                label: 'Message outbox',
                onTap: () {
                  Navigator.pop(context);
                  _showOutbox();
                },
              ),
            _MenuTile(
              icon: Icons.timer_outlined,
              label:
                  'Disappearing messages${_messageExpiry == null ? '' : ' · ${_expiryLabel(_messageExpiry!)}'}',
              onTap: () {
                Navigator.pop(context);
                _chooseMessageExpiry();
              },
            ),
            _MenuTile(
              icon: Icons.person_outlined,
              label: 'View profile',
              onTap: () {
                Navigator.pop(context);
                final peer = _peer;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (peer == null) {
                    _unsupported(
                        "That profile is still loading. Try again in a moment.");
                    return;
                  }
                  context.push('/profile/${peer.id}');
                });
              },
            ),
            _MenuTile(
              icon: Icons.auto_awesome_outlined,
              label: 'Friendship timeline',
              onTap: () {
                Navigator.pop(context);
                final peer = _peer;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (peer == null) {
                    _unsupported(
                        "That friendship is still loading. Try again in a moment.");
                    return;
                  }
                  context.push('/friendship-timeline/${peer.id}', extra: peer);
                });
              },
            ),
            if (!_conversationLocked)
              _MenuTile(
                icon: Icons.lock_outlined,
                label: 'Lock conversation',
                onTap: () {
                  Navigator.pop(context);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _lockConversation();
                  });
                },
              )
            else
              _MenuTile(
                icon: Icons.lock_open_outlined,
                label: 'Unlock conversation',
                onTap: () {
                  Navigator.pop(context);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _unlockConversation();
                  });
                },
              ),
            _MenuTile(
              icon: Icons.report_outlined,
              label: 'Report user',
              onTap: () {
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _reportUser();
                });
              },
            ),
            _MenuTile(
              icon: Icons.block_flipped,
              label: 'Block user',
              onTap: () {
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _blockUser();
                });
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _reportUser() async {
    final peer = _peer;
    if (peer == null) {
      _unsupported("That profile is still loading. Try again in a moment.");
      return;
    }
    final detailsCtrl = TextEditingController();
    String chosen = 'spam';
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: _P.surface,
            title: Text('Report @${peer.username}',
                style: const TextStyle(color: _P.text)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Why are you reporting this person?',
                      style: TextStyle(color: _P.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: chosen,
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => chosen = v);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final option in const [
                          ('spam', 'Spam'),
                          ('harassment', 'Harassment'),
                          ('hate', 'Hate or abuse'),
                          ('other', 'Something else'),
                        ])
                          RadioListTile<String>(
                            dense: true,
                            value: option.$1,
                            title: Text(option.$2,
                                style: const TextStyle(color: _P.text)),
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: detailsCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: _P.text),
                    decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                      hintText: 'What happened?',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Submit report')),
            ],
          ),
        ),
      );
      if (submitted != true) return;
      await Supa.reportUser(
        userId: peer.id,
        reason: chosen,
        details:
            detailsCtrl.text.trim().isEmpty ? null : detailsCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Thanks. We received your report.')));
      }
    } catch (e) {
      _unsupported(friendlyErrorMessage(e,
          fallback: "We couldn't send that report. Try again?"));
    } finally {
      detailsCtrl.dispose();
    }
  }

  Future<void> _blockUser() async {
    final peer = _peer;
    if (peer == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _P.surface,
        title: Text('Block @${peer.username}?',
            style: const TextStyle(color: _P.text)),
        content: const Text(
            'You will no longer receive messages or calls from this person.',
            style: TextStyle(color: _P.muted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await Supa.blockUser(peer.id);
      if (mounted) context.pop(); // Close the chat screen
    }
  }

  Future<void> _showReactionPicker(Message message) async {
    // If the message already has reactions, toggle them directly by tapping
    // the reaction row. This picker is only for adding new reactions.
    await showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'React to message',
                style: TextStyle(
                    color: _P.text, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: const [
                  '👍',
                  '❤️',
                  '😂',
                  '😮',
                  '😢',
                  '😡',
                  '🎉',
                  '👏',
                  '🙏',
                  '🔥',
                ].map((emoji) => _ReactionPickerItem(emoji: emoji)).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).then((emoji) {
      if (emoji != null && emoji is String) {
        Supa.addReaction(message.id, emoji);
      }
    });
  }

  /// Toggle a reaction on a message (add if not present, remove if present).
  Future<void> _toggleReaction(String messageId, String emoji) async {
    final reactions = await Supa.getReactions(messageId);
    final me = Supa.currentUser;
    if (me == null) return;
    final hasReacted =
        reactions.any((r) => r['emoji'] == emoji && r['user_id'] == me.id);
    if (hasReacted) {
      await Supa.removeReaction(messageId, emoji);
    } else {
      await Supa.addReaction(messageId, emoji);
    }
  }

  /// Show the edit history for a message.
  Future<void> _showEditHistory(Message message) async {
    try {
      final history = await Supa.fetchEditHistory(message.id);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Edit history'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: history.length,
              itemBuilder: (context, index) {
                final entry = history[index];
                final editedAt = DateTime.parse(entry['edited_at'] as String);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit ${index + 1} · ${_formatDateTime(editedAt)}',
                        style: const TextStyle(
                            color: _P.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _P.surfaceHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Before:',
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                            Text(
                              entry['previous_content'] as String,
                              style:
                                  const TextStyle(color: _P.text, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'After:',
                              style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                            Text(
                              entry['new_content'] as String,
                              style:
                                  const TextStyle(color: _P.text, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'))
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        _unsupported(
            friendlyErrorMessage(e, fallback: "Couldn't load edit history."));
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = date.difference(today).inDays;
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'Today at $time';
    if (diff == -1) return 'Yesterday at $time';
    return '${dt.month}/${dt.day}/${dt.year} at $time';
  }

  Future<void> _showMessageActions(Message message) async {
    final isMine = message.senderId == Supa.currentUser!.id;
    final now = DateTime.now();
    final messageAge = now.difference(message.createdAt);
    final canEdit = isMine &&
        messageAge <= const Duration(minutes: 15) &&
        !message.content.startsWith('attachment:');
    final canDeleteForEveryone =
        isMine && messageAge <= const Duration(hours: 1);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _P.surface,
      builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isMine)
          ListTile(
              leading: Icon(message.pinnedAt == null
                  ? Icons.push_pin_outlined
                  : Icons.push_pin),
              title: Text(
                  message.pinnedAt == null ? 'Pin message' : 'Unpin message'),
              onTap: () => Navigator.pop(sheetContext, 'pin')),
        if (canEdit)
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit message'),
              onTap: () => Navigator.pop(sheetContext, 'edit')),
        if (canDeleteForEveryone)
          ListTile(
              leading: const Icon(Icons.delete_forever_outlined,
                  color: Colors.redAccent),
              title: const Text('Delete for everyone',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(sheetContext, 'delete_for_everyone')),
        ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Delete for me',
                style: TextStyle(color: Colors.redAccent)),
            onTap: () => Navigator.pop(sheetContext, 'delete')),
        ListTile(
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: const Text('Add reaction'),
            onTap: () => Navigator.pop(sheetContext, 'react')),
        if (message.editedAt != null)
          ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('View edit history'),
              onTap: () => Navigator.pop(sheetContext, 'edit_history')),
        ListTile(
            leading: const Icon(Icons.reply_outlined),
            title: const Text('Reply'),
            onTap: () => Navigator.pop(sheetContext, 'reply')),
        ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () => Navigator.pop(sheetContext, 'copy')),
        const SizedBox(height: 8),
      ])),
    );
    try {
      if (action == 'pin') {
        await Supa.setMessagePinned(message.id, message.pinnedAt == null,
            conversationId: widget.conversationId);
      }
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: message.content));
      }
      if (action == 'edit_history' && mounted) {
        await _showEditHistory(message);
      }
      if (action == 'edit' && mounted) {
        final controller = TextEditingController(text: message.content);
        final updated = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Edit message'),
                  content: TextField(
                      controller: controller, autofocus: true, maxLines: 4),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(
                            dialogContext, controller.text.trim()),
                        child: const Text('Save'))
                  ],
                ));
        controller.dispose();
        if (updated != null &&
            updated.isNotEmpty &&
            updated != message.content) {
          await Supa.updateMessage(message.id, updated);
        }
      }
      if (action == 'delete_for_everyone' && mounted) {
        final confirm = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Delete for everyone'),
                  content: const Text(
                      'This will remove the message for all participants. This action cannot be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent),
                        child: const Text('Delete for everyone'))
                  ],
                ));
        if (confirm == true) {
          await Supa.deleteMessageForEveryone(message.id);
        }
      }
      if (action == 'delete' && mounted) {
        final confirm = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Delete for me'),
                  content: const Text(
                      'This will remove the message only from your view.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent),
                        child: const Text('Delete'))
                  ],
                ));
        if (confirm == true) {
          await Supa.deleteMessage(message.id);
        }
      }
      if (action == 'react') {
        _showReactionPicker(message);
      }
      if (action == 'reply' && mounted) {
        setState(() => _replyTo = message);
      }
    } catch (e) {
      if (mounted) {
        _unsupported(friendlyErrorMessage(e,
            fallback: "We couldn't update that message. Please try again."));
      }
    }
  }

  void _showAttachSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _P.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _AttachActionItem(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: const Color(0xFF8B5CF6),
                    onTap: () {
                      Navigator.pop(context);
                      _pickPhoto();
                    },
                  ),
                  _AttachActionItem(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: const Color(0xFFEC4899),
                    onTap: () {
                      Navigator.pop(context);
                      _pickPhoto(camera: true);
                    },
                  ),
                  _AttachActionItem(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'Document',
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      Navigator.pop(context);
                      _pickDocument();
                    },
                  ),
                  _AttachActionItem(
                    icon: Icons.gif_box_rounded,
                    label: 'GIF',
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      Navigator.pop(context);
                      _showGifPicker();
                    },
                  ),
                  _AttachActionItem(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Stickers',
                    color: _P.primary,
                    iconColor: _P.darkOnAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _showStickerPicker();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show an emoji picker bottom sheet and insert the chosen emoji.
  void _showEmojiPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 300,
          child: _EmojiPicker(onEmojiSelected: (emoji) {
            _ctrl.text += emoji;
            _ctrl.selection = TextSelection.fromPosition(
              TextPosition(offset: _ctrl.text.length),
            );
            Navigator.pop(context);
          }),
        ),
      ),
    );
  }

  /// Show a schedule picker dialog to schedule the current message text.
  Future<void> _showSchedulePicker() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      _unsupported('Type a message first, then tap the schedule icon.');
      return;
    }

    final now = DateTime.now();
    DateTime selectedDate = now.add(const Duration(hours: 1)).copyWith(
          second: 0,
          millisecond: 0,
          microsecond: 0,
        );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _P.surface,
          title:
              const Text('Schedule message', style: TextStyle(color: _P.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This message will be sent at:\n'
                '${DateFormat('EEEE, MMMM d · h:mm a').format(selectedDate)}',
                style: const TextStyle(color: _P.text, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today,
                          size: 18, color: _P.primary),
                      label: Text(
                        DateFormat('MMM d').format(selectedDate),
                        style: const TextStyle(color: _P.text, fontSize: 13),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDate,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setLocal(() {
                            selectedDate = selectedDate.copyWith(
                              year: picked.year,
                              month: picked.month,
                              day: picked.day,
                            );
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time,
                          size: 18, color: _P.primary),
                      label: Text(
                        DateFormat('h:mm a').format(selectedDate),
                        style: const TextStyle(color: _P.text, fontSize: 13),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(selectedDate),
                        );
                        if (picked != null) {
                          setLocal(() {
                            selectedDate = selectedDate.copyWith(
                              hour: picked.hour,
                              minute: picked.minute,
                            );
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _SchedulePresetBtn('1 hr', const Duration(hours: 1), setLocal,
                      now, (d) => selectedDate = d),
                  _SchedulePresetBtn('Tomorrow', const Duration(days: 1),
                      setLocal, now, (d) => selectedDate = d),
                  _SchedulePresetBtn('Next week', const Duration(days: 7),
                      setLocal, now, (d) => selectedDate = d),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Schedule')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await scheduled.ScheduledMessages.schedule(
        conversationId: widget.conversationId,
        content: text,
        scheduledAt: selectedDate.toUtc(),
        replyToId: _replyTo?.id,
      );
      if (mounted) {
        _ctrl.clear();
        setState(() => _replyTo = null);
        _unsupported('Message scheduled! ⏰');
      }
    } catch (e) {
      if (mounted) {
        _unsupported(friendlyErrorMessage(e,
            fallback: "Couldn't schedule the message. Try again."));
      }
    }
  }

  /// Show a GIF picker using the Giphy API.
  Future<void> _showGifPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 450,
          child: _GifPicker(onGifSelected: (gifUrl) async {
            Navigator.pop(context);
            try {
              final attachment = await Supa.uploadAttachmentFromUrl(
                  widget.conversationId, gifUrl, 'gif');
              await Supa.sendMessage(widget.conversationId,
                  'attachment:${jsonEncode(attachment)}');
              if (mounted) _rollToBottom();
            } catch (e) {
              if (mounted) {
                _unsupported(friendlyErrorMessage(e,
                    fallback: "Couldn't send that GIF. Please try again."));
              }
            }
          }),
        ),
      ),
    );
  }

  /// Show a sticker picker and send the chosen sticker.
  Future<void> _showStickerPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 350,
          child: _StickerPicker(onStickerSelected: (sticker) async {
            Navigator.pop(context);
            try {
              // Send sticker as a large emoji text message
              await Supa.sendMessage(widget.conversationId, sticker);
              if (mounted) _rollToBottom();
            } catch (e) {
              if (mounted) {
                _unsupported(friendlyErrorMessage(e,
                    fallback: "Couldn't send that sticker. Please try again."));
              }
            }
          }),
        ),
      ),
    );
  }

  Future<void> _sendAttachment(
      Uint8List bytes, String name, String mimeType) async {
    final senderId = Supa.currentUser?.id;
    if (senderId == null || _sendingMessage) return;
    if (bytes.length > 20 * 1024 * 1024) {
      _unsupported('Files must be 20 MB or smaller.');
      return;
    }
    setState(() => _sendingMessage = true);
    final localId = const Uuid().v4();
    final expiresAt =
        _messageExpiry == null ? null : DateTime.now().add(_messageExpiry!);
    try {
      final attachment = await Supa.uploadAttachment(
          widget.conversationId, bytes, name, mimeType);
      if (!mounted || Supa.currentUser?.id != senderId) return;
      final pending = PendingMessage(
        localId: localId,
        conversationId: widget.conversationId,
        senderId: senderId,
        content: 'attachment:${jsonEncode(attachment)}',
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
      );
      try {
        await _addPending(pending);
        await Supa.sendMessage(
          widget.conversationId,
          pending.content,
          expectedSenderId: senderId,
        );
        _removePending(localId);
        if (Supa.currentUser?.id == senderId) _rollToBottom();
      } catch (e) {
        _markPendingFailed(pending);
        if (Supa.currentUser?.id == senderId) {
          _unsupported(friendlyErrorMessage(e,
              fallback:
                  "We couldn't upload that file. Check your connection and try again."));
        }
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  String _mimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp4' || 'mov' => 'video/$ext',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt' => 'text/plain',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _pickPhoto({bool camera = false}) async {
    try {
      final picker = ImagePicker();
      final file = camera
          ? await picker.pickImage(
              source: ImageSource.camera, imageQuality: 85, maxWidth: 1920)
          : await picker.pickMedia(imageQuality: 85, maxWidth: 1920);
      if (file == null) return;
      await _sendAttachment(
          await file.readAsBytes(), file.name, _mimeType(file.name));
    } catch (_) {
      _unsupported("We couldn't open your photos. Please try again.");
    }
  }

  Future<void> _pickDocument() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        _unsupported('Files must be 20 MB or smaller.');
        return;
      }
      await _sendAttachment(bytes, file.name, _mimeType(file.name));
    } catch (_) {
      _unsupported("We couldn't open that file. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lockReady && _conversationLocked && !_conversationUnlocked) {
      return LockGate(
        title: 'This chat is locked',
        reason: 'Unlock this conversation',
        onUnlocked: () => setState(() => _conversationUnlocked = true),
      );
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'Back to chats',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/conversations');
            }
          },
        ),
        title: InkWell(
          onTap: () {
            final peer = _peer;
            if (peer != null) context.push('/profile/${peer.id}');
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: Presence.epoch,
                  builder: (_, __, ___) => Avatar(
                    name: _peer?.peerInitial ?? '?',
                    url: _peer?.avatarUrl,
                    digitalConfig: _peer?.avatarConfig,
                    size: 38,
                    showOnlineDot:
                        _peerTyping == null && Presence.isOnline(_peer?.id),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _peer?.label ?? 'Chat',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _P.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      _PeerStatusLine(
                        typing: _peerTyping != null,
                        peerId: _peer?.id,
                        fallback: _peer != null
                            ? '@${_peer!.username}'
                            : 'Direct message',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          // E2EE security indicator
          Tooltip(
            message: 'Messages are end-to-end encrypted',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.lock_rounded,
                size: 18,
                color: Colors.green.shade300,
              ),
            ),
          ),
          _ActionBtn(Icons.videocam_rounded,
              onTap: () => _startCall(video: true)),
          _ActionBtn(Icons.phone_rounded,
              onTap: () => _startCall(video: false)),
          _ActionBtn(Icons.more_vert, onTap: () => _showChatMenu(context)),
          const SizedBox(width: 6),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > _adaptiveBreakpoint) {
            return _buildLargeScreenChat(context);
          } else {
            return _buildSmallScreenChat(context);
          }
        },
      ),
    );
  }

  Widget _buildSmallScreenChat(BuildContext context) {
    return StreamBuilder<List<Message>>(
      stream: Supa.watchMessages(widget.conversationId),
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        final display = _displayMessages(messages);
        final pinnedMessages = messages
            .where((m) => m.pinnedAt != null)
            .toList()
          ..sort((a, b) => (b.pinnedAt!).compareTo(a.pinnedAt!));
        final showBanner = pinnedMessages.isNotEmpty && !_pinnedBannerDismissed;

        return Column(
          children: [
            // Pinned message banner
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => SizeTransition(
                sizeFactor: anim,
                alignment: Alignment.topCenter,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: showBanner
                  ? _PinnedMessagesBanner(
                      key: const ValueKey('banner'),
                      pinnedMessages: pinnedMessages,
                      currentIndex: _pinnedBannerIndex.clamp(
                          0, pinnedMessages.length - 1),
                      onTap: () {
                        final idx = _pinnedBannerIndex.clamp(
                            0, pinnedMessages.length - 1);
                        final msg = pinnedMessages[idx];
                        final msgIdx = messages.indexOf(msg);
                        if (msgIdx >= 0) {
                          _scrollToMessage(msgIdx, messages.length);
                        }
                        setState(() {
                          _pinnedBannerIndex =
                              (_pinnedBannerIndex + 1) % pinnedMessages.length;
                        });
                      },
                      onLongPress: () => _showPinnedMessagesSheet(
                        context,
                        pinnedMessages,
                        (i, total) {
                          final msg = pinnedMessages[
                              i.clamp(0, pinnedMessages.length - 1)];
                          final msgIdx = messages.indexOf(msg);
                          if (msgIdx >= 0) {
                            _scrollToMessage(msgIdx, messages.length);
                          }
                        },
                        (msg) async {
                          await Supa.setMessagePinned(msg.id, false);
                        },
                      ),
                      onDismiss: () =>
                          setState(() => _pinnedBannerDismissed = true),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-banner')),
            ),
            Expanded(
              child: Container(
                decoration: _chatCanvas(_chatBackground,
                    imageUrl: _chatBackgroundImageUrl),
                child: Builder(builder: (context) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      display.isEmpty) {
                    return const BubbleSkeleton();
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(
                        message: "Couldn't load this chat",
                        detail: 'A quick retry usually does the trick.',
                        onRetry: () => setState(() {}));
                  }
                  if (display.isEmpty) {
                    return _EmptyState(
                      peerName: _peer?.label,
                      onSayHello: () {
                        _ctrl.text = 'Hey! 👋';
                        _send();
                      },
                    );
                  }
                  _markUnreadAsReadIfNeeded(messages);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            itemCount: display.length,
                            itemBuilder: (_, i) => _MessageRow(
                              msg: display[i],
                              prev: i > 0 ? display[i - 1] : null,
                              next: i + 1 < display.length
                                  ? display[i + 1]
                                  : null,
                              me: Supa.currentUser!.id,
                              onLongPress: _showMessageActions,
                              onReactionTap: _toggleReaction,
                              messages: display,
                              pendingStatus:
                                  _pendingMessages[display[i].id]?.status,
                            ),
                          ),
                          Positioned(
                            bottom: 12,
                            right: 16,
                            child: AnimatedScale(
                              scale: _showJumpToBottom ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutBack,
                              child: AnimatedOpacity(
                                opacity: _showJumpToBottom ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 160),
                                child: PressScale(
                                  onTap: _jumpToBottom,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _P.surfaceHigh,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            _P.primary.withValues(alpha: 0.4),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: _P.primary,
                                        size: 26,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (_peerTyping != null) const _TypingIndicator(),
            if (_replyTo != null)
              _ReplyPreviewBar(
                message: _replyTo!,
                onCancel: () => setState(() => _replyTo = null),
              ),
            _Composer(
              controller: _ctrl,
              onSend: _send,
              onTypingChanged: _onTypingChanged,
              onAttach: () => _showAttachSheet(context),
              onVoice: () => _openVoiceNote(),
              onEmoji: _showEmojiPicker,
              onSchedule: _showSchedulePicker,
            ),
          ],
        );
      },
    );
  }

  Widget _buildLargeScreenChat(BuildContext context) {
    return Row(
      children: [
        const NavSidebar(),
        Expanded(
          child: StreamBuilder<List<Message>>(
            stream: Supa.watchMessages(widget.conversationId),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];
              final display = _displayMessages(messages);
              final pinnedMessages = messages
                  .where((m) => m.pinnedAt != null)
                  .toList()
                ..sort((a, b) => (b.pinnedAt!).compareTo(a.pinnedAt!));
              final showBanner =
                  pinnedMessages.isNotEmpty && !_pinnedBannerDismissed;

              return Column(
                children: [
                  // Pinned message banner
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => SizeTransition(
                      sizeFactor: anim,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: showBanner
                        ? _PinnedMessagesBanner(
                            key: const ValueKey('banner'),
                            pinnedMessages: pinnedMessages,
                            currentIndex: _pinnedBannerIndex.clamp(
                                0, pinnedMessages.length - 1),
                            onTap: () {
                              final idx = _pinnedBannerIndex.clamp(
                                  0, pinnedMessages.length - 1);
                              final msg = pinnedMessages[idx];
                              final msgIdx = messages.indexOf(msg);
                              if (msgIdx >= 0) {
                                _scrollToMessage(msgIdx, messages.length);
                              }
                              setState(() {
                                _pinnedBannerIndex = (_pinnedBannerIndex + 1) %
                                    pinnedMessages.length;
                              });
                            },
                            onLongPress: () => _showPinnedMessagesSheet(
                              context,
                              pinnedMessages,
                              (i, total) {
                                final msg = pinnedMessages[
                                    i.clamp(0, pinnedMessages.length - 1)];
                                final msgIdx = messages.indexOf(msg);
                                if (msgIdx >= 0) {
                                  _scrollToMessage(msgIdx, messages.length);
                                }
                              },
                              (msg) async {
                                await Supa.setMessagePinned(msg.id, false);
                              },
                            ),
                            onDismiss: () =>
                                setState(() => _pinnedBannerDismissed = true),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-banner')),
                  ),
                  Expanded(
                    child: Container(
                      decoration: _chatCanvas(_chatBackground,
                          imageUrl: _chatBackgroundImageUrl),
                      child: Builder(builder: (context) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            messages.isEmpty) {
                          return const BubbleSkeleton();
                        }
                        if (snapshot.hasError) {
                          return _ErrorState(
                              message: "Couldn't load this chat",
                              detail: 'A quick retry usually does the trick.',
                              onRetry: _onRetry);
                        }
                        if (messages.isEmpty) {
                          return _EmptyState(
                            peerName: _peer?.label,
                            onSayHello: () {
                              _ctrl.text = 'Hey! 👋';
                              _send();
                            },
                          );
                        }
                        _markUnreadAsReadIfNeeded(messages);
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Stack(
                              children: [
                                ListView.builder(
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  itemCount: display.length,
                                  itemBuilder: (_, i) => _MessageRow(
                                    msg: display[i],
                                    prev: i > 0 ? display[i - 1] : null,
                                    next: i + 1 < display.length
                                        ? display[i + 1]
                                        : null,
                                    me: Supa.currentUser!.id,
                                    onLongPress: _showMessageActions,
                                    onReactionTap: _toggleReaction,
                                    messages: display,
                                    pendingStatus:
                                        _pendingMessages[display[i].id]?.status,
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  right: 16,
                                  child: AnimatedScale(
                                    scale: _showJumpToBottom ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutBack,
                                    child: AnimatedOpacity(
                                      opacity: _showJumpToBottom ? 1.0 : 0.0,
                                      duration:
                                          const Duration(milliseconds: 160),
                                      child: PressScale(
                                        onTap: _jumpToBottom,
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: _P.surfaceHigh,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _P.primary
                                                  .withValues(alpha: 0.4),
                                              width: 1.2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: _P.primary,
                                              size: 26,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (_peerTyping != null) const _TypingIndicator(),
                  if (_replyTo != null)
                    _ReplyPreviewBar(
                      message: _replyTo!,
                      onCancel: () => setState(() => _replyTo = null),
                    ),
                  _Composer(
                    controller: _ctrl,
                    onSend: _send,
                    onTypingChanged: _onTypingChanged,
                    onAttach: () => _showAttachSheet(context),
                    onVoice: () => _openVoiceNote(),
                    onEmoji: _showEmojiPicker,
                    onSchedule: _showSchedulePicker,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.peerName, this.onSayHello});
  final String? peerName;
  final VoidCallback? onSayHello;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _P.surface,
                shape: BoxShape.circle,
                border: Border.all(color: _P.border),
              ),
              child: const Center(
                child: Icon(Icons.waving_hand_outlined,
                    color: _P.primary, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              peerName != null ? 'Say hello to $peerName!' : 'No messages yet',
              style: const TextStyle(
                color: _P.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Break the ice with a message or a quick wave.',
              style: TextStyle(color: _P.muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (onSayHello != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onSayHello,
                style: FilledButton.styleFrom(
                  backgroundColor: _P.surfaceHigh,
                  foregroundColor: _P.text,
                ),
                icon: const Text('👋', style: TextStyle(fontSize: 16)),
                label: const Text('Wave hello',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message, this.detail, required this.onRetry});
  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: _P.muted, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _P.text, fontSize: 16, fontWeight: FontWeight.w600)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _P.muted, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerStatusLine extends StatelessWidget {
  const _PeerStatusLine({
    required this.typing,
    required this.peerId,
    required this.fallback,
  });
  final bool typing;
  final String? peerId;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: typing
          ? const Row(
              key: ValueKey('typing'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('typing',
                    style: TextStyle(fontSize: 12, color: _P.primary)),
                SizedBox(width: 4),
                _TypingDots(color: _P.primary, size: 4),
              ],
            )
          : ValueListenableBuilder<int>(
              key: const ValueKey('presence'),
              valueListenable: Presence.epoch,
              builder: (_, __, ___) {
                final game = Presence.game(peerId)?.playingLabel;
                if (game != null) {
                  return GamePresenceTag(label: game, color: _P.primary);
                }
                final presence = Presence.label(peerId) ?? fallback;
                final online = Presence.isOnline(peerId);
                return Text(
                  presence,
                  style: TextStyle(
                    fontSize: 12,
                    color: online ? _P.success : _P.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({this.color = _P.muted, this.size = 6});
  final Color color;
  final double size;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: widget.size * 0.45),
              _dot(i),
            ],
          ],
        );
      },
    );
  }

  Widget _dot(int index) {
    final t = (_ctrl.value + index / 3) % 1;
    final bounce = (t < 0.5 ? t : 1 - t) * 2;
    final lift = (bounce * 3) - 0.4;
    final opacity = 0.35 + bounce * 0.65;
    return Transform.translate(
      offset: Offset(0, -lift),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _P.surfaceHigh,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
            border: Border.all(color: _P.border),
          ),
          child: const _TypingDots(color: _P.muted, size: 7),
        ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(
      {required this.msg,
      this.prev,
      this.next,
      required this.me,
      required this.onLongPress,
      this.onReactionTap,
      this.messages,
      this.pendingStatus});
  final Message msg;
  final Message? prev;
  final Message? next;
  final String me;
  final ValueChanged<Message> onLongPress;
  final void Function(String messageId, String emoji)? onReactionTap;
  final List<Message>? messages;
  final String? pendingStatus;

  bool get _nowDateLine =>
      prev == null || !_sameDay(prev!.createdAt, msg.createdAt);
  bool get _groupPrev =>
      prev != null && prev!.senderId == msg.senderId && !_nowDateLine;
  bool get _groupNext =>
      next != null &&
      next!.senderId == msg.senderId &&
      _sameDay(msg.createdAt, next!.createdAt);
  bool get mine => msg.senderId == me;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (_nowDateLine) _DateLine(ts: msg.createdAt),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (context, progress, child) => Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(
                (mine ? 1 : -1) * 10 * (1 - progress),
                7 * (1 - progress),
              ),
              child: child,
            ),
          ),
          child: _Bubble(
            msg: msg,
            groupedTop: _groupPrev,
            groupedBottom: _groupNext,
            mine: mine,
            onLongPress: () => onLongPress(msg),
            onReactionTap: onReactionTap,
            pendingStatus: pendingStatus,
            replyTarget: msg.replyToId != null && messages != null
                ? messages!.where((m) => m.id == msg.replyToId).firstOrNull
                : null,
          ),
        ),
      ],
    );
  }
}

class _DateLine extends StatelessWidget {
  const _DateLine({required this.ts});
  final DateTime ts;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (_MessageRow._sameDay(now, ts)) {
      label = 'Today';
    } else if (_MessageRow._sameDay(
        now.subtract(const Duration(days: 1)), ts)) {
      label = 'Yesterday';
    } else {
      label = '${ts.day} ${_months[ts.month - 1]}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _P.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _P.border),
          ),
          child: Text(label,
              style: const TextStyle(color: _P.muted, fontSize: 12)),
        ),
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({
    required this.reactions,
    required this.mine,
    this.onTap,
  });
  final List<Map<String, dynamic>> reactions;
  final bool mine;
  final ValueChanged<String>? onTap;

  Map<String, int> get _counts {
    final counts = <String, int>{};
    for (final r in reactions) {
      final emoji = r['emoji'] as String;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  bool _hasUserReacted(String emoji) {
    final me = Supa.currentUser;
    if (me == null) return false;
    return reactions.any((r) => r['emoji'] == emoji && r['user_id'] == me.id);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final uniqueEmojis = counts.keys.toList();
    final mutedColor = mine ? _P.darkOnAccent.withValues(alpha: 0.5) : _P.muted;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: uniqueEmojis.map((emoji) {
        final count = counts[emoji]!;
        final hasReacted = _hasUserReacted(emoji);
        return GestureDetector(
          onTap: onTap != null ? () => onTap!(emoji) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hasReacted
                  ? _P.volt.withValues(alpha: 0.15)
                  : _P.surfaceLow.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: hasReacted
                  ? Border.all(color: _P.volt, width: 1)
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.08), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hasReacted ? _P.volt : mutedColor,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VoiceMessage extends StatefulWidget {
  const _VoiceMessage({required this.content, required this.mine});
  final String content;
  final bool mine;

  @override
  State<_VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<_VoiceMessage> {
  final _player = AudioPlayer();
  String? _path;
  bool _ready = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  /// Extracts the object path from the `voice:<json>` message content.
  Future<void> _parse() async {
    try {
      final meta =
          jsonDecode(widget.content.substring(6)) as Map<String, dynamic>;
      if (meta['path'] != null) {
        setState(() {
          _path = meta['path'] as String;
          _ready = true;
        });
      }
    } catch (_) {
      // Malformed voice note content; fall back to a placeholder bubble.
    }
  }

  void _toggle() {
    if (_path == null) return;
    if (_playing) {
      _player.pause();
    } else {
      _player.play(UrlSource(_path!));
    }
    setState(() => _playing = !_playing);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _filename() {
    try {
      final raw = widget.content.substring(6);
      final parts = raw.split('/');
      final last = parts.last.split('}').first;
      return '$last.m4a';
    } catch (_) {
      return 'voice note';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: widget.mine
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_P.primary, Color(0xFFC7EF00)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF292B32), Color(0xFF202127)],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.mine
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: widget.mine
                ? _P.primary.withValues(alpha: 0.13)
                : Colors.black.withValues(alpha: 0.16),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.audio_file_outlined,
                  color: _P.darkOnAccent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _filename(),
                  style: TextStyle(
                      color: widget.mine ? _P.darkOnAccent : _P.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: widget.mine ? _P.darkOnAccent : _P.text,
                ),
                onPressed: _toggle,
                tooltip: _playing ? 'Pause' : 'Play',
              ),
            ],
          ),
          if (_path != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _ready
                  ? SizedBox(
                      height: 40,
                      child: _playing
                          ? const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _P.darkOnAccent))
                          : Icon(
                              _playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: widget.mine ? _P.darkOnAccent : _P.text,
                              size: 32),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _VoiceNoteDialog extends StatefulWidget {
  const _VoiceNoteDialog({required this.conversationId});
  final String conversationId;

  @override
  State<_VoiceNoteDialog> createState() => _VoiceNoteDialogState();
}

class _VoiceNoteDialogState extends State<_VoiceNoteDialog> {
  bool _recording = false;
  bool _sending = false;
  String? _error;

  Future<void> _toggleRecord() async {
    if (_recording) {
      setState(() {
        _recording = false;
        _error = null;
        _sending = true;
      });
      final messageId =
          await VoiceNoteService.stopAndUpload(widget.conversationId);
      if (!mounted) return;
      setState(() => _sending = false);
      if (messageId.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Voice note sent.'),
              behavior: SnackBarBehavior.floating),
        );
        Navigator.of(context).pop(messageId);
      } else {
        setState(() {
          _recording = true;
          _error =
              'Could not send that voice note. Check your connection and try again.';
        });
      }
    } else {
      final ok = await VoiceNoteService.start();
      if (!mounted) return;
      if (ok) {
        setState(() => _recording = true);
      } else {
        setState(() {
          _error = 'Microphone permission is needed for voice notes.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: _P.bg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _recording ? 'Recording…' : 'Voice note',
                  style: const TextStyle(fontSize: 20, color: _P.text),
                ),
                const SizedBox(height: 6),
                Text(
                  _recording
                      ? 'Hold to record, tap stop when done.'
                      : 'Tap and hold to record a voice note.',
                  style: TextStyle(color: _P.muted, height: 1.4),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _error ?? '',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 120,
            child: GestureDetector(
              onTap: _toggleRecord,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _recording
                      ? const Color(0xFF450A0A)
                      : _sending
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _recording
                        ? const Color(0xFF8A0000)
                        : const Color(0xFF444444),
                    width: 2,
                  ),
                ),
                child: _recording
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Recording',
                              style: TextStyle(
                                  color: _P.darkOnAccent, fontSize: 16)),
                          SizedBox(height: 6),
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _P.darkOnAccent,
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(
                          _recording ? Icons.stop_rounded : Icons.mic_outlined,
                          color: _recording ? _P.darkOnAccent : _P.text,
                          size: 44,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.msg,
      this.groupedTop = false,
      this.groupedBottom = false,
      required this.mine,
      required this.onLongPress,
      this.onReactionTap,
      this.replyTarget,
      this.pendingStatus});
  final Message msg;
  final bool groupedTop;
  final bool groupedBottom;
  final bool mine;
  final VoidCallback onLongPress;
  final void Function(String messageId, String emoji)? onReactionTap;
  final Message? replyTarget;
  final String? pendingStatus;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? attachment;
    if (msg.content.startsWith('attachment:')) {
      try {
        attachment = Map<String, dynamic>.from(
            jsonDecode(msg.content.substring(11)) as Map);
      } catch (_) {}
    }
    final adjusted = BorderRadius.only(
      topLeft: Radius.circular(!mine && groupedTop ? 7 : 18),
      topRight: Radius.circular(mine && groupedTop ? 7 : 18),
      bottomLeft: Radius.circular(!mine && groupedBottom ? 7 : 18),
      bottomRight: Radius.circular(mine && groupedBottom ? 7 : 18),
    );
    return Padding(
      padding: EdgeInsets.only(
        top: groupedTop ? 2 : 6,
        bottom: groupedBottom ? 2 : 6,
        left: mine ? 64 : 4,
        right: mine ? 4 : 64,
      ),
      child: GestureDetector(
        onLongPress: () {
          if (attachment != null) return;
          onLongPress();
        },
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: mine
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_P.primary, Color(0xFFC7EF00)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF292B32), Color(0xFF202127)],
                  ),
            borderRadius: adjusted,
            border: Border.all(
              color: mine
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: mine
                    ? _P.primary.withValues(alpha: 0.13)
                    : Colors.black.withValues(alpha: 0.16),
                blurRadius: mine ? 18 : 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyTarget != null)
                _ReplyPreviewInline(msg: replyTarget!, mine: mine),
              if (msg.content.startsWith('voice:'))
                _VoiceMessage(content: msg.content, mine: mine)
              else if (attachment != null)
                _AttachmentContent(attachment: attachment, mine: mine)
              else
                Text(msg.content,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.3,
                        color: mine ? _P.darkOnAccent : _P.text)),
              if (msg.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                _ReactionsRow(
                  reactions: msg.reactions,
                  mine: mine,
                  onTap: onReactionTap != null
                      ? (emoji) => onReactionTap!(msg.id, emoji)
                      : null,
                ),
              ],
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msg.pinnedAt != null) ...[
                    Icon(Icons.push_pin,
                        size: 11, color: mine ? _P.darkOnAccent : _P.primary),
                    const SizedBox(width: 3),
                  ],
                  if (msg.editedAt != null) ...[
                    Text('edited',
                        style: TextStyle(
                            fontSize: 10,
                            color: mine
                                ? _P.darkOnAccent.withValues(alpha: 0.7)
                                : _P.muted)),
                    const SizedBox(width: 4),
                  ],
                  Text(_fmtTime(msg.createdAt),
                      style: TextStyle(
                          fontSize: 11,
                          color: mine
                              ? _P.darkOnAccent.withValues(alpha: 0.7)
                              : _P.muted)),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    if (pendingStatus == 'sending') ...[
                      const SizedBox(width: 2),
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: _P.darkOnAccent.withValues(alpha: 0.6),
                        ),
                      ),
                    ] else if (pendingStatus == 'failed') ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.error_outline_rounded,
                        size: 13,
                        color: Colors.red.shade900,
                      ),
                    ] else ...[
                      Icon(
                        msg.readByPeer
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 13,
                        color: msg.readByPeer
                            ? const Color(0xFF0D5E2F)
                            : _P.darkOnAccent.withValues(alpha: 0.7),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(DateTime t) {
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}

class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({required this.attachment, required this.mine});
  final Map<String, dynamic> attachment;
  final bool mine;
  @override
  Widget build(BuildContext context) {
    final previewWidth =
        (MediaQuery.sizeOf(context).width * 0.58).clamp(120.0, 220.0);
    final objectPath = attachment['path'] as String?;
    final name = attachment['name'] as String? ?? 'Shared file';
    if (objectPath == null) {
      return Text(name, style: const TextStyle(color: _P.text));
    }
    return FutureBuilder<String>(
      future: Supa.attachmentUrl(objectPath),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(
            width: 220,
            child: TextButton.icon(
              onPressed: () async {
                try {
                  final url = await Supa.attachmentUrl(objectPath);
                  await launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              "This file isn't ready yet. Try again in a moment.")),
                    );
                  }
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Couldn't open this file"),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
              width: 180,
              height: 54,
              child: Center(child: BroSpinner(size: 18)));
        }
        final url = Uri.parse(snapshot.data!);
        if (attachment['kind'] == 'image') {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (dialogContext) => Dialog.fullscreen(
                        backgroundColor: Colors.black.withValues(alpha: 0.95),
                        child: Stack(
                          children: [
                            InteractiveViewer(
                              maxScale: 4.0,
                              child: Center(
                                child: Image.network(url.toString(),
                                    fit: BoxFit.contain),
                              ),
                            ),
                            Positioned(
                              top: 24,
                              right: 20,
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white, size: 28),
                                onPressed: () => Navigator.pop(dialogContext),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(url.toString(),
                          width: previewWidth,
                          height: 190,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => SizedBox(
                              width: previewWidth,
                              height: 100,
                              child: const Icon(Icons.broken_image_outlined)))),
                ),
                const SizedBox(height: 5),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: mine ? _P.darkOnAccent : _P.text)),
              ]);
        }
        return InkWell(
            onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  attachment['kind'] == 'video'
                      ? Icons.video_file_outlined
                      : Icons.insert_drive_file_outlined,
                  color: mine ? _P.darkOnAccent : _P.primary),
              const SizedBox(width: 8),
              Flexible(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: mine ? _P.darkOnAccent : _P.text,
                            fontWeight: FontWeight.w600)),
                    Text('Tap to open',
                        style: TextStyle(
                            fontSize: 11,
                            color: mine
                                ? _P.darkOnAccent.withValues(alpha: 0.7)
                                : _P.muted)),
                  ])),
            ]));
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    this.onTypingChanged,
    this.onAttach,
    this.onVoice,
    this.onEmoji,
    this.onSchedule,
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String>? onTypingChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onVoice;
  final VoidCallback? onEmoji;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _P.border.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            PressScale(
              scaleFactor: 0.88,
              onTap: onAttach,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.add_circle_outline_rounded,
                    color: _P.primary, size: 24),
              ),
            ),
            PressScale(
              scaleFactor: 0.88,
              onTap: onEmoji,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.emoji_emotions_outlined,
                    color: _P.muted, size: 22),
              ),
            ),
            PressScale(
              scaleFactor: 0.88,
              onTap: onSchedule,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.schedule_outlined, color: _P.muted, size: 22),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: _P.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(
                      color: _P.muted.withValues(alpha: 0.7), fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => onSend(),
                onChanged: onTypingChanged,
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, __) {
                final hasText = v.text.trim().isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.only(right: 6, left: 4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(
                        opacity: anim,
                        child: child,
                      ),
                    ),
                    child: hasText
                        ? PressScale(
                            key: const ValueKey('send-btn'),
                            scaleFactor: 0.88,
                            onTap: onSend,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _P.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _P.primary.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.arrow_upward_rounded,
                                  color: _P.darkOnAccent,
                                  size: 21,
                                ),
                              ),
                            ),
                          )
                        : PressScale(
                            key: const ValueKey('mic-btn'),
                            scaleFactor: 0.88,
                            onTap: onVoice,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _P.surfaceHigh,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _P.border.withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.mic_none_rounded,
                                  color: _P.primary,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.icon, {this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return IconButton(
        icon: Icon(icon, color: _P.muted, size: 22), onPressed: onTap ?? () {});
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _P.muted, size: 22),
      title: Text(label, style: const TextStyle(color: _P.text, fontSize: 15)),
      onTap: onTap,
    );
  }
}

class _AttachActionItem extends StatelessWidget {
  const _AttachActionItem({
    required this.icon,
    required this.label,
    required this.color,
    this.iconColor = Colors.white,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scaleFactor: 0.9,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: color == _P.primary ? iconColor : color,
                size: 24,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: _P.text,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// === Chat widgets ===

class _ReactionPickerItem extends StatelessWidget {
  const _ReactionPickerItem({required this.emoji});
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, emoji),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _P.border),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}

class _ReplyPreviewBar extends StatelessWidget {
  const _ReplyPreviewBar({required this.message, required this.onCancel});
  final Message message;
  final VoidCallback onCancel;

  String get _previewText {
    final text = message.content;
    if (text.startsWith('attachment:')) return '[Attachment]';
    return text.isEmpty ? '[Empty message]' : text;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _P.volt.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _P.volt.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.reply_outlined, size: 16, color: _P.volt),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reply to',
                    style: TextStyle(color: _P.volt, fontSize: 11),
                  ),
                  Text(
                    _previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _P.text.withValues(alpha: 0.7), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: _P.muted),
              onPressed: onCancel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reply preview shown inside a message bubble when the message is a reply.

class _ReplyPreviewInline extends StatelessWidget {
  const _ReplyPreviewInline({required this.msg, required this.mine});
  final Message msg;
  final bool mine;

  String get _previewText {
    final text = msg.content;
    if (text.startsWith('attachment:')) return '[Attachment]';
    return text.isEmpty ? '[Empty message]' : text;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = mine ? _P.darkOnAccent.withValues(alpha: 0.6) : _P.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.reply_outlined, size: 12, color: textColor),
              const SizedBox(width: 4),
              Text(
                'Reply to${msg.senderId == (Supa.currentUser?.id ?? '') ? ' you' : ''}',
                style: TextStyle(fontSize: 11, color: textColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            constraints: const BoxConstraints(maxWidth: 250),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: textColor.withValues(alpha: 0.15)),
            ),
            child: Text(
              _previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Emoji picker grid with categorized emojis.

class _EmojiPicker extends StatelessWidget {
  const _EmojiPicker({required this.onEmojiSelected});
  final ValueChanged<String> onEmojiSelected;

  static const _emojis = {
    'Smileys': [
      '😀',
      '😃',
      '😄',
      '😁',
      '😆',
      '😅',
      '🤣',
      '😂',
      '🙂',
      '🙃',
      '😉',
      '😊',
      '😇',
      '🥰',
      '😍',
      '🤩',
      '😘',
      '😗',
      '😚',
      '😙',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤑',
      '🤗',
      '🤭',
      '🤫',
      '🤔',
      '🤐',
      '🤨',
      '😐',
      '😑',
      '😶',
      '😏',
      '😒',
      '🙄',
      '😬',
      '🤥',
      '😌',
      '😔',
      '😪',
      '🤤',
      '😴',
      '😷',
      '🤒',
      '🤕',
      '🤢',
      '🤮',
      '🤧',
      '🥵',
      '🥶',
      '🥴',
      '😵',
      '🤯',
      '🤠',
      '🥳',
      '🥸',
      '😎',
      '🤓',
      '🧐',
      '😕',
      '😟',
      '🙁',
      '😮',
      '😯',
      '😲',
      '😳',
      '🥺',
      '😦',
      '😧',
      '😨',
      '😰',
      '😥',
      '😢',
      '😭',
      '😱',
      '😖',
      '😣',
      '😞',
      '😓',
      '😩',
      '😫',
      '🥱',
      '😤',
      '😡',
      '😠',
      '🤬',
      '😈',
      '👿',
      '💀',
      '☠️',
      '💩',
      '🤡',
      '👹',
      '👺',
      '👻',
      '👽',
      '👾',
      '🤖',
    ],
    'Gestures': [
      '👋',
      '🤚',
      '🖐️',
      '✋',
      '🖖',
      '👌',
      '🤌',
      '🤏',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '🤙',
      '👈',
      '👉',
      '👆',
      '🖕',
      '👇',
      '☝️',
      '👍',
      '👎',
      '✊',
      '👊',
      '🤛',
      '🤜',
      '👏',
      '🙌',
      '👐',
      '🤲',
      '🤝',
      '🙏',
      '✍️',
      '💅',
      '🤳',
      '💪',
    ],
    'Hearts': [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '♥️',
      '🫶',
    ],
    'Objects': [
      '⚡',
      '🔥',
      '✨',
      '🎉',
      '🎊',
      '🎈',
      '🎁',
      '🏆',
      '🥇',
      '🎯',
      '🚀',
      '💡',
      '📌',
      '🔔',
      '🎵',
      '🎶',
      '🎸',
      '🥁',
      '🎤',
      '🎧',
      '📱',
      '💻',
      '🎮',
      '🕹️',
      '📷',
      '🎬',
      '🎨',
      '🧩',
      '🎲',
      '🃏',
      '♟️',
    ],
    'Nature': [
      '🌈',
      '☀️',
      '🌤️',
      '⛅',
      '🌦️',
      '🌧️',
      '⛈️',
      '🌩️',
      '🌨️',
      '❄️',
      '☃️',
      '⛄',
      '🌬️',
      '💨',
      '🌪️',
      '🌫️',
      '🌊',
      '💧',
      '💦',
      '🌸',
      '💐',
      '🌷',
      '🌹',
      '🌺',
      '🌻',
      '🌼',
      '🌵',
      '🌴',
      '🌳',
      '🌲',
      '🍀',
      '🍁',
      '🍂',
      '🍃',
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🦆',
      '🦅',
      '🦉',
      '🦋',
      '🐛',
      '🐌',
      '🐞',
      '🐜',
      '🪲',
      '🐢',
      '🐍',
      '🐙',
      '🦑',
      '🐬',
      '🐳',
      '🐋',
      '🦈',
      '🐊',
    ],
    'Food': [
      '🍕',
      '🍔',
      '🍟',
      '🌭',
      '🥪',
      '🌮',
      '🌯',
      '🥙',
      '🍜',
      '🍝',
      '🍣',
      '🍱',
      '🍛',
      '🍤',
      '🍙',
      '🍚',
      '🍳',
      '🥘',
      '🍲',
      '🥗',
      '🍿',
      '🧂',
      '🥫',
      '🍞',
      '🥐',
      '🥖',
      '🥨',
      '🧀',
      '🥚',
      '🥓',
      '🥩',
      '🍗',
      '🍖',
      '🦴',
      '🌽',
      '🥕',
      '🥦',
      '🍆',
      '🥔',
      '🍠',
      '🌰',
      '🥜',
      '🍯',
      '🍎',
      '🍏',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍈',
      '🍒',
      '🍑',
      '🥭',
      '🍍',
      '🥥',
      '🥝',
      '🍅',
      '🍄',
      '🥜',
      '🌶️',
      '🍺',
      '🍻',
      '🥂',
      '🍷',
      '🥃',
      '🍸',
      '🍹',
      '🧃',
      '🥤',
      '🧋',
      '☕',
      '🍵',
      '🫖',
      '🍶',
      '🧊',
      '🍰',
      '🎂',
      '🧁',
      '🥧',
      '🍩',
      '🍪',
      '🍫',
      '🍬',
      '🍭',
      '🍮',
      '🍯',
    ],
    'Travel': [
      '🚗',
      '🚕',
      '🚙',
      '🚌',
      '🚎',
      '🏎️',
      '🚓',
      '🚑',
      '🚒',
      '🚐',
      '🛻',
      '🚚',
      '🚛',
      '🚜',
      '🏍️',
      '🛵',
      '🚲',
      '🛴',
      '🛹',
      '🚁',
      '✈️',
      '🛩️',
      '🚀',
      '🛸',
      '🚢',
      '⛵',
      '🚤',
      '🗼',
      '🏰',
      '🏯',
      '🏟️',
      '🎡',
      '🎢',
      '🎠',
      '⛲',
      '🗽',
      '🌅',
      '🌄',
      '🌠',
      '🎇',
      '🎆',
      '🌉',
      '🌇',
      '🌆',
      '🏙️',
      '🌃',
      '🌌',
      '🌍',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text('Emoji',
              style: TextStyle(
                  color: _P.text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: _emojis.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 4),
                        child: Text(entry.key,
                            style: TextStyle(
                                color: _P.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: entry.value.map((emoji) {
                          return InkWell(
                            onTap: () => onEmojiSelected(emoji),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              child: Text(emoji,
                                  style: const TextStyle(fontSize: 24)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// GIF picker using the Giphy API (trending + search).

class _GifPicker extends StatefulWidget {
  const _GifPicker({required this.onGifSelected});
  final ValueChanged<String> onGifSelected;

  @override
  State<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<_GifPicker> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _gifs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() => _loading = true);
    try {
      final gifs = await _fetchGifs('trending');
      if (mounted) setState(() => _gifs = gifs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchGifs() async {
    final query = _search.text.trim();
    if (query.isEmpty) {
      _loadTrending();
      return;
    }
    setState(() => _loading = true);
    try {
      final gifs = await _fetchGifs('search', query: query);
      if (mounted) setState(() => _gifs = gifs);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchGifs(
    String type, {
    String? query,
  }) async {
    // Use Giphy's public API. The key is a demo key; for production, use your own.
    final apiKey = 'dc6FjTznNgl7dPyRzO9cYI7zF2fCHP0s';
    final uri = switch (type) {
      'trending' => Uri.https('api.giphy.com', '/v1/gifs/trending', {
          'api_key': apiKey,
          'limit': '20',
          'rating': 'g',
        }),
      'search' => Uri.https('api.giphy.com', '/v1/gifs/search', {
          'api_key': apiKey,
          'q': query!,
          'limit': '20',
          'rating': 'g',
        }),
      _ => throw Exception('Unknown type'),
    };
    final response = await http.get(uri);
    if (response.statusCode != 200) throw Exception('API error');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = data['data'] as List<dynamic>? ?? [];
    return results
        .whereType<Map<String, dynamic>>()
        .where((g) {
          final images = g['images'] as Map<String, dynamic>?;
          return images?['fixed_height']?['url'] != null;
        })
        .map((g) => {
              'url': (g['images']['fixed_height'] as Map)['url'] as String,
              'preview': (g['images']['fixed_height_downsampled'] as Map)['url']
                  as String?,
              'title': g['title'] as String? ?? '',
            })
        .toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text('GIF',
              style: TextStyle(
                  color: _P.text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search GIFs...',
              hintStyle: const TextStyle(color: _P.muted),
              prefixIcon: const Icon(Icons.search, color: _P.muted),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: _P.muted),
                      onPressed: () {
                        _search.clear();
                        _loadTrending();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _P.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _P.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _P.primary)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(color: _P.text),
            onSubmitted: (_) => _searchGifs(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _gifs.isEmpty
                    ? const Center(
                        child: Text('No GIFs found',
                            style: TextStyle(color: _P.muted)))
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _gifs.length,
                        itemBuilder: (context, index) {
                          final gif = _gifs[index];
                          final url = gif['preview'] ?? gif['url'];
                          return InkWell(
                            onTap: () =>
                                widget.onGifSelected(gif['url'] as String),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: _P.surfaceHigh,
                                  child: const Icon(Icons.broken_image,
                                      color: _P.muted),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Sticker picker with built-in sticker packs.

class _StickerPicker extends StatelessWidget {
  const _StickerPicker({required this.onStickerSelected});
  final ValueChanged<String> onStickerSelected;

  static const _stickerPacks = {
    'Faces': [
      '😂',
      '🤣',
      '😍',
      '🥰',
      '😎',
      '🤩',
      '😇',
      '🥳',
      '😴',
      '🤯',
      '😱',
      '🤮',
      '💀',
      '👻',
      '🤡',
      '👽',
      '🤖',
      '😈',
      '👿',
      '🙃',
      '😏',
      '🤔',
      '🤫',
      '🤭',
    ],
    'Hands': [
      '👍',
      '👎',
      '👏',
      '🙌',
      '👐',
      '🤝',
      '🙏',
      '✌️',
      '🤞',
      '🤟',
      '🤘',
      '👌',
      '🤏',
      '✋',
      '🖖',
      '👋',
      '💪',
      '🦾',
      '🖕',
      '👊',
      '🤛',
      '🤜',
    ],
    'Love': [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
      '🫶',
      '😘',
      '😍',
      '🥰',
      '😻',
      '💑',
      '💏',
      '👩‍❤️‍👨',
      '👨‍❤️‍👨',
      '👩‍❤️‍👩',
    ],
    'Animals': [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🦆',
      '🦅',
      '🦉',
      '🦇',
      '🐛',
      '🦋',
      '🐌',
      '🐞',
      '🐜',
      '🪲',
      '🐢',
      '🐍',
      '🦎',
      '🐙',
      '🦑',
      '🐬',
      '🐳',
      '🐋',
      '🦈',
      '🐊',
      '🐅',
      '🐆',
      '🦓',
      '🦍',
      '🦧',
      '🐘',
      '🦛',
      '🦏',
      '🐪',
      '🐫',
      '🦒',
      '🦘',
      '🦬',
      '🐃',
      '🐂',
      '🐄',
      '🐎',
      '🐖',
      '🐏',
      '🐑',
      '🦙',
      '🐐',
      '🦌',
      '🐕',
      '🐩',
      '🦮',
      '🐕‍🦺',
      '🐈',
      '🐈‍⬛',
      '🐓',
      '🦃',
      '🦤',
      '🦚',
      '🦜',
      '🦢',
      '🦩',
      '🕊️',
      '🐇',
      '🦝',
      '🦨',
      '🦡',
      '🦫',
      '🦦',
      '🦥',
      '🐁',
      '🐀',
      '🐿️',
      '🦔',
    ],
    'Activities': [
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🥎',
      '🎾',
      '🏐',
      '🏉',
      '🥏',
      '🎱',
      '🪀',
      '🏓',
      '🏸',
      '🏒',
      '🏑',
      '🥍',
      '🏏',
      '🪃',
      '🥅',
      '⛳',
      '🪁',
      '🏹',
      '🎣',
      '🤿',
      '🥊',
      '🥋',
      '🎽',
      '🛹',
      '🛼',
      '🛷',
      '⛸️',
      '🥌',
      '🎿',
      '⛷️',
      '🏂',
      '🪂',
      '🏋️',
      '🤸',
      '⛹️',
      '🤺',
      '🏇',
      '🧘',
      '🏄',
      '🏊',
      '🤽',
      '🚣',
      '🧗',
      '🚴',
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🏅',
      '🎖️',
      '🏵️',
      '🎗️',
      '🎫',
      '🎟️',
      '🎪',
    ],
    'Travel': [
      '🚗',
      '🚕',
      '🚙',
      '🚌',
      '🏎️',
      '🚓',
      '🚑',
      '🚒',
      '🚐',
      '🚚',
      '🚛',
      '🚜',
      '🏍️',
      '🛵',
      '🚲',
      '🛴',
      '🚁',
      '✈️',
      '🛩️',
      '🚀',
      '🛸',
      '🚢',
      '⛵',
      '🚤',
      '🗼',
      '🏰',
      '🏯',
      '🏟️',
      '🎡',
      '🎢',
      '🎠',
      '⛲',
      '🗽',
      '🌅',
      '🌄',
      '🌠',
      '🎇',
      '🎆',
      '🌉',
      '🌇',
      '🌆',
      '🏙️',
      '🌃',
      '🌌',
      '🌍',
      '🌎',
      '🌏',
      '🗾',
    ],
    'Objects': [
      '⌚',
      '📱',
      '💻',
      '⌨️',
      '🖥️',
      '🖨️',
      '🖱️',
      '🖲️',
      '💽',
      '💾',
      '💿',
      '📀',
      '📼',
      '📷',
      '📸',
      '📹',
      '🎥',
      '📽️',
      '🎞️',
      '📞',
      '☎️',
      '📟',
      '📠',
      '📺',
      '📻',
      '🎙️',
      '🎚️',
      '🎛️',
      '🧭',
      '⏱️',
      '⏲️',
      '⏰',
      '🕰️',
      '⌛',
      '⏳',
      '📡',
      '🔋',
      '🔌',
      '💡',
      '🔦',
      '🕯️',
      '🧯',
      '🗑️',
      '🛢️',
      '💸',
      '💵',
      '💴',
      '💶',
      '💷',
      '💰',
      '💳',
      '💎',
      '⚖️',
      '🧰',
      '🔧',
      '🔨',
      '⚒️',
      '🛠️',
      '⛏️',
      '🪚',
      '🔩',
      '⚙️',
      '🧱',
      '⛓️',
      '🧲',
      '🔗',
      '📧',
      '📨',
      '📩',
      '📤',
      '📥',
      '📦',
      '📫',
      '📪',
      '📬',
      '📭',
      '📮',
      '📯',
      '📜',
      '📃',
      '📄',
      '📑',
      '🧾',
      '📊',
      '📈',
      '📉',
      '📆',
      '📅',
      '🗓️',
      '📇',
      '🗃️',
      '🗳️',
      '🗄️',
      '📋',
      '📁',
      '📂',
      '🗂️',
      '🗞️',
      '📰',
      '📓',
      '📔',
      '📒',
      '📕',
      '📗',
      '📘',
      '📙',
      '📚',
      '📖',
      '🔖',
      '🧷',
      '🔗',
      '📎',
      '🖇️',
      '📐',
      '📏',
      '🧮',
      '📌',
      '📍',
      '✂️',
      '🖊️',
      '🖋️',
      '✒️',
      '🖌️',
      '🖍️',
      '📝',
      '✏️',
      '🔍',
      '🔎',
      '🔏',
      '🔐',
      '🔒',
      '🔓',
    ],
    'Symbols': [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '☮️',
      '✝️',
      '☪️',
      '🕉️',
      '☸️',
      '✡️',
      '🔯',
      '🕎',
      '☯️',
      '☦️',
      '🛐',
      '⛎',
      '♈',
      '♉',
      '♊',
      '♋',
      '♌',
      '♍',
      '♎',
      '♏',
      '♐',
      '♑',
      '♒',
      '♓',
      '🆔',
      '⚛️',
      '🉑',
      '☢️',
      '☣️',
      '📴',
      '📳',
      '🈶',
      '🈚',
      '🈸',
      '🈺',
      '🈷️',
      '✴️',
      '🆚',
      '💮',
      '🉐',
      '㊙️',
      '㊗️',
      '🈴',
      '🈵',
      '🈹',
      '🈲',
      '🅰️',
      '🅱️',
      '🆎',
      '🆑',
      '🅾️',
      '🆘',
      '❌',
      '⭕',
      '🛑',
      '⛔',
      '📛',
      '🚫',
      '💯',
      '💢',
      '♨️',
      '🚷',
      '🚯',
      '🚳',
      '🚱',
      '🔞',
      '📵',
      '🚭',
      '❗',
      '❕',
      '❓',
      '❔',
      '‼️',
      '⁉️',
      '🔅',
      '🔆',
      '〽️',
      '⚠️',
      '🚸',
      '🔱',
      '⚜️',
      '🔰',
      '♻️',
      '✅',
      '🈯',
      '💹',
      '❇️',
      '✳️',
      '❎',
      '🌐',
      '💠',
      'Ⓜ️',
      '🌀',
      '💤',
      '🏧',
      '🚾',
      '♿',
      '🅿️',
      '🛗',
      '🈳',
      '🈂️',
      '🛂',
      '🛃',
      '🛄',
      '🛅',
      '🚹',
      '🚺',
      '🚼',
      '⚧️',
      '🚻',
      '🚮',
      '🎦',
      '📶',
      '🈁',
      '🔣',
      'ℹ️',
      '🔤',
      '🔡',
      '🔠',
      '🆖',
      '🆗',
      '🆙',
      '🆒',
      '🆕',
      '🆓',
      '0️⃣',
      '1️⃣',
      '2️⃣',
      '3️⃣',
      '4️⃣',
      '5️⃣',
      '6️⃣',
      '7️⃣',
      '8️⃣',
      '9️⃣',
      '🔟',
      '🔢',
      '#️⃣',
      '*️⃣',
      '⏏️',
      '▶️',
      '⏸️',
      '⏯️',
      '⏹️',
      '⏺️',
      '⏭️',
      '⏮️',
      '⏩',
      '⏪',
      '⏫',
      '⏬',
      '◀️',
      '🔼',
      '🔽',
      '➡️',
      '⬅️',
      '⬆️',
      '⬇️',
      '↗️',
      '↘️',
      '↙️',
      '↖️',
      '↕️',
      '↔️',
      '↪️',
      '↩️',
      '⤴️',
      '⤵️',
      '🔀',
      '🔁',
      '🔂',
      '🔄',
      '🔃',
      '➕',
      '➖',
      '➗',
      '✖️',
      '🟰',
      '♾️',
      '💲',
      '💱',
      '™️',
      '©️',
      '®️',
      '〰️',
      '➰',
      '➿',
      '🔚',
      '🔙',
      '🔛',
      '🔝',
      '🔜',
      '✔️',
      '☑️',
      '🔘',
      '🔴',
      '🟠',
      '🟡',
      '🟢',
      '🔵',
      '🟣',
      '🟤',
      '⚫',
      '⚪',
      '🟥',
      '🟧',
      '🟨',
      '🟩',
      '🟦',
      '🟪',
      '🟫',
      '⬛',
      '⬜',
      '◼️',
      '◻️',
      '◾',
      '◽',
      '▪️',
      '▫️',
      '🔶',
      '🔷',
      '🔸',
      '🔹',
      '🔺',
      '🔻',
      '💠',
      '🔲',
      '🔳',
      '⬬',
      '🔈',
      '🔇',
      '🔉',
      '🔊',
      '🔔',
      '🔕',
      '📣',
      '📢',
      '♠️',
      '♣️',
      '♥️',
      '♦️',
      '🃏',
      '🎴',
      '🀄',
      '🕐',
      '🕑',
      '🕒',
      '🕓',
      '🕔',
      '🕕',
      '🕖',
      '🕗',
      '🕘',
      '🕙',
      '🕚',
      '🕛',
      '🕜',
      '🕝',
      '🕞',
      '🕟',
      '🕠',
      '🕡',
      '🕢',
      '🕣',
      '🕤',
      '🕥',
      '🕦',
      '🕧',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text('Stickers',
              style: TextStyle(
                  color: _P.text, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: _stickerPacks.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 4),
                        child: Text(entry.key,
                            style: TextStyle(
                                color: _P.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.value.map((sticker) {
                          return InkWell(
                            onTap: () => onStickerSelected(sticker),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _P.surfaceHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(sticker,
                                  style: const TextStyle(fontSize: 32)),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick-preset button for the schedule picker dialog.

class _SchedulePresetBtn extends StatelessWidget {
  final String label;
  final Duration duration;
  final void Function(VoidCallback) setState;
  final DateTime now;
  final void Function(DateTime) onSelected;
  const _SchedulePresetBtn(
      this.label, this.duration, this.setState, this.now, this.onSelected);

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        final d = now
            .add(duration)
            .copyWith(second: 0, millisecond: 0, microsecond: 0);
        onSelected(d);
        setState(() {});
      },
      child:
          Text(label, style: const TextStyle(color: _P.primary, fontSize: 13)),
    );
  }
}

class _PinnedMessagesBanner extends StatelessWidget {
  const _PinnedMessagesBanner({
    super.key,
    required this.pinnedMessages,
    required this.currentIndex,
    required this.onTap,
    required this.onLongPress,
    required this.onDismiss,
  });

  final List<Message> pinnedMessages;
  final int currentIndex;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (pinnedMessages.isEmpty) return const SizedBox.shrink();

    final count = pinnedMessages.length;
    // Show the message at currentIndex (clamped for safety).
    final msg = pinnedMessages[currentIndex.clamp(0, count - 1)];
    final preview = msg.content.replaceAll('\n', ' ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: count > 1 ? onLongPress : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _P.surface,
            border: Border(
              bottom: BorderSide(color: _P.border.withValues(alpha: 0.6)),
              left: BorderSide(color: _P.primary, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              // Pin icon
              Icon(Icons.push_pin, size: 15, color: _P.primary),
              const SizedBox(width: 10),
              // Message preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "Pinned message" label + counter
                    Row(
                      children: [
                        Text(
                          'Pinned message',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _P.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (count > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _P.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${currentIndex + 1} / $count',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _P.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: _P.text.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              // Dismiss button
              GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.close,
                      size: 16, color: _P.muted.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing all pinned messages with tap-to-scroll and unpin.
void _showPinnedMessagesSheet(
  BuildContext context,
  List<Message> pinnedMessages,
  void Function(int index, int total) onScrollTo,
  Future<void> Function(Message msg) onUnpin,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: _P.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => _PinnedMessagesSheet(
      pinnedMessages: pinnedMessages,
      onScrollTo: onScrollTo,
      onUnpin: onUnpin,
    ),
  );
}

class _PinnedMessagesSheet extends StatefulWidget {
  const _PinnedMessagesSheet({
    required this.pinnedMessages,
    required this.onScrollTo,
    required this.onUnpin,
  });

  final List<Message> pinnedMessages;
  final void Function(int index, int total) onScrollTo;
  final Future<void> Function(Message msg) onUnpin;

  @override
  State<_PinnedMessagesSheet> createState() => _PinnedMessagesSheetState();
}

class _PinnedMessagesSheetState extends State<_PinnedMessagesSheet> {
  // Track local unpin in-progress to show loading feedback.
  final _unpinning = <String>{};

  @override
  Widget build(BuildContext context) {
    final msgs = widget.pinnedMessages;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _P.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 18, color: _P.primary),
                const SizedBox(width: 8),
                Text(
                  'Pinned messages',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _P.text,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _P.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${msgs.length} / 5',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _P.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _P.border),
          // Message list – show most recent first
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: msgs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _P.border),
              itemBuilder: (_, i) {
                final msg = msgs[i];
                final isUnpinning = _unpinning.contains(msg.id);
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _P.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _P.primary,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    msg.content.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: _P.text),
                  ),
                  subtitle: Text(
                    _fmtBannerTime(msg.pinnedAt ?? msg.createdAt),
                    style: TextStyle(fontSize: 11, color: _P.muted),
                  ),
                  trailing: isUnpinning
                      ? const BroSpinner(size: 18, color: _P.muted)
                      : IconButton(
                          icon: Icon(Icons.push_pin, size: 18, color: _P.muted),
                          tooltip: 'Unpin',
                          onPressed: () async {
                            setState(() => _unpinning.add(msg.id));
                            try {
                              await widget.onUnpin(msg);
                            } finally {
                              if (mounted) {
                                setState(() => _unpinning.remove(msg.id));
                              }
                            }
                          },
                        ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onScrollTo(i, msgs.length);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _fmtBannerTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inDays == 0) {
      final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
      final m = t.minute.toString().padLeft(2, '0');
      final ap = t.hour >= 12 ? 'PM' : 'AM';
      return 'Pinned today at $h:$m $ap';
    }
    if (diff.inDays == 1) return 'Pinned yesterday';
    if (diff.inDays < 7) return 'Pinned ${diff.inDays} days ago';
    return 'Pinned ${t.day}/${t.month}/${t.year}';
  }
}
