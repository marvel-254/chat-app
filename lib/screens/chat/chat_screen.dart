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
import '../../services/voice_note.dart';
import '../../services/scheduled_messages.dart' as scheduled;
import '../../services/secure_screen.dart';
import '../../models/profile.dart';
import '../../models/pending_message.dart';
import '../../ui/states.dart';
import '../../ui/errors.dart';
import '../../ui/motion.dart';
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
        // Applied broadly - every conversation has screenshot protection enabled
        // when the chat screen is active, with additional locking available
        // via the conversation lock feature.
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
              content: Text(
                  '${peer.label} (@${peer.username}) is calling.',
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
    Supa.chatBackgroundChanged.removeListener(_chatBackgroundListener);
    final callChannel = _callChannel;
    if (callChannel != null) Supa.client.removeChannel(callChannel);
    super.dispose();
  }

  Future<void> _openVoiceNote() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _VoiceNoteDialog(conversationId: widget.conversationId),
    );
    if (result != null && result.isNotEmpty) {
      // The dialog already played a short confirmation; nothing further needed.
    }
  }

  Future<void> _send() async {
    final draft = _ctrl.text;
    final content = draft.trim();
    if (content.isEmpty || _sendingMessage) return;

    setState(() => _sendingMessage = true);
    _typingTimer?.cancel();
    _selfTyping = false;
    unawaited(Supa.broadcastTyping(widget.conversationId, false));
    final replyToId = _replyTo?.id;
    final localId = const Uuid().v4();
    final expiresAt =
        _messageExpiry == null ? null : DateTime.now().add(_messageExpiry!);
    try {
      final pending = PendingMessage(
        localId: localId,
        conversationId: widget.conversationId,
        senderId: Supa.currentUser!.id,
        content: content,
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
        replyToId: replyToId,
      );
      _addPending(pending);
      await Supa.sendMessage(widget.conversationId, content,
          expiry: _messageExpiry, replyToId: replyToId);
      _removePending(localId);
      // Trigger chat list refresh so the sender sees the updated preview
      Supa.triggerConversationRefresh();
      if (!mounted) return;
      if (_ctrl.text == draft) _ctrl.clear();
      setState(() => _replyTo = null);
      unawaited(Supa.saveDraft(widget.conversationId, ''));
      _rollToBottom();
    } catch (e) {
      _markPendingFailed(localId);
      if (mounted) {
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
  void _addPending(PendingMessage pm) {
    _pendingMessages[pm.localId] = pm;
  }

  void _removePending(String localId) {
    _pendingMessages.remove(localId);
  }

  void _markPendingFailed(String localId) {
    final pm = _pendingMessages[localId];
    if (pm != null && pm.status != 'sent') {
      pm.status = 'failed';
      pm.retryCount += 1;
      setState(() {});
    }
  }

  /// The messages the UI should render: server rows merged with in-flight
  /// pending rows, deduplicated and sorted oldest-to-newest.
  List<Message> _displayMessages(List<Message> serverMessages) {
    final pending = _pendingMessages.values
        .where((pm) => pm.status == 'sending' || pm.status == 'failed')
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

  void _showChatMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                              style: const TextStyle(color: _P.text, fontSize: 14),
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
                              style: const TextStyle(color: _P.text, fontSize: 14),
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
                  ]));
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
                      'This will remove the message for all participants. This action cannot be undone.',
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
                )));
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
                      'This will remove the message only from your view.',
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
    if (_sendingMessage) return;
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
      final pending = PendingMessage(
        localId: localId,
        conversationId: widget.conversationId,
        senderId: Supa.currentUser!.id,
        content: 'attachment:${jsonEncode(attachment)}',
        createdAt: DateTime.now(),
        expiresAt: expiresAt,
      );

[read_files: showing lines 1-1416 of 5123. The window was shortened to stay under 50,000 characters. Use code_search to locate the part you need and read a window around it, or call read_files again with offset=1417 to continue.]"]