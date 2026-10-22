import 'dart:async';

import 'package:flutter/material.dart';

void main() => runApp(const VantasticApp());

const _indigo = Color(0xFF6366F1);
const _indigoDeep = Color(0xFF3B3E8F);
const _bg = Color(0xFF0E0F13);
const _surface = Color(0xFF17181D);
const _border = Color(0xFF26272E);
const _text = Color(0xFFE8EAED);
const _muted = Color(0xFF8A8C94);

// Single palette — keep design consistent everywhere.
class _P {
  static const bg = _bg;
  static const surface = _surface;
  static const border = _border;
  static const text = _text;
  static const muted = _muted;
  static const primary = _indigo;
}

class VantasticApp extends StatelessWidget {
  const VantasticApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vantastic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _P.bg,
        colorScheme: ColorScheme.dark(
          primary: _P.primary,
          surface: _P.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _P.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: _P.text),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [
    _Msg(DateTime.now().subtract(const Duration(minutes: 6)), 'Hey! Welcome to Vantastic.', false, read: true),
    _Msg(DateTime.now().subtract(const Duration(minutes: 5)), 'Type a message below and hit send.', false, read: true),
    _Msg(DateTime.now().subtract(const Duration(minutes: 4)), 'Messages group automatically as they arrive, with the time shown on each one.', false, read: true),
  ];
  bool _typing = false;

  void _send() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    final now = DateTime.now();
    setState(() {
      _typing = true;
      _msgs.add(_Msg(now, t, true, read: false));
    });
    _ctrl.clear();
    _rollToBottom();
    Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _typing = false;
        _msgs.last = _Msg(now, _msgs.last.text, true, read: true);
        _msgs.add(_Msg(DateTime.now(), 'Got it: "$t"', false, read: true));
      });
      _rollToBottom();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leadingWidth: 64,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16, top: 2),
          child: _Avatar(name: 'A', size: 40),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pulse', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _P.text)),
            Text('online', style: TextStyle(fontSize: 12, color: _P.primary)),
          ],
        ),
        actions: const [
          _ActionBtn(Icons.videocam_rounded),
          _ActionBtn(Icons.phone_rounded),
          _ActionBtn(Icons.more_vert),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _MessageRow(
                      msg: _msgs[i],
                      prev: i > 0 ? _msgs[i - 1] : null,
                      next: i + 1 < _msgs.length ? _msgs[i + 1] : null,
                    ),
                  ),
          ),
          if (_typing) const _TypingIndicator(),
          _Composer(controller: _ctrl, onSend: _send),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.forum_outlined, color: _P.muted, size: 56),
          SizedBox(height: 16),
          Text('No messages yet', style: TextStyle(color: _P.muted, fontSize: 15)),
          SizedBox(height: 4),
          Text('Say hello to get started.', style: TextStyle(color: _P.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('Pulse is typing…', style: TextStyle(color: _P.muted, fontSize: 12, fontStyle: FontStyle.italic)),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.msg, this.prev, this.next});
  final _Msg msg;
  final _Msg? prev;
  final _Msg? next;

  bool get _nowDateLine => prev == null || !_sameDay(prev!.ts, msg.ts);
  bool get _groupPrev => !msg.mine && prev != null && !prev!.mine && !_nowDateLine;
  bool get _groupNext => !msg.mine && next != null && !next!.mine && _sameDay(msg.ts, next!.ts);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: msg.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (_nowDateLine) _DateLine(ts: msg.ts),
        _Bubble(msg: msg, groupedTop: _groupPrev, groupedBottom: _groupNext),
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
    } else if (_MessageRow._sameDay(now.subtract(const Duration(days: 1)), ts)) {
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
          child: Text(label, style: const TextStyle(color: _P.muted, fontSize: 12)),
        ),
      ),
    );
  }
}
const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, this.groupedTop = false, this.groupedBottom = false});
  final _Msg msg;
  final bool groupedTop;
  final bool groupedBottom;

  @override
  Widget build(BuildContext context) {
    final mine = msg.mine;
    final adjusted = BorderRadius.only(
      topLeft: Radius.circular(mine || !groupedTop ? 18 : 6),
      topRight: Radius.circular(18),
      bottomLeft: Radius.circular(mine ? (groupedBottom ? 6 : 18) : 18),
      bottomRight: Radius.circular(mine ? 18 : (groupedBottom ? 6 : 18)),
    );
    return Padding(
      padding: EdgeInsets.only(
        top: groupedTop ? 2 : 6,
        bottom: groupedBottom ? 2 : 6,
        left: mine ? 64 : 4,
        right: mine ? 4 : 64,
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? _P.primary : _P.surface,
          borderRadius: adjusted,
          border: mine ? null : Border.all(color: _P.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg.text, style: TextStyle(fontSize: 15, height: 1.3, color: mine ? Colors.white : _P.text)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmtTime(msg.ts), style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : _P.muted)),
                if (mine) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.read ? Icons.done_all : Icons.done_all,
                    size: 13,
                    color: msg.read ? const Color(0xFFB9FBC0) : Colors.white70,
                  ),
                ],
              ],
            ),
          ],
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

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _P.border),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            const Icon(Icons.add_rounded, color: _P.muted),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: _P.text, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(color: _P.muted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, v, __) {
                final hasText = v.text.trim().isNotEmpty;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: hasText
                      ? IconButton.filled(
                          key: const ValueKey('send'),
                          onPressed: onSend,
                          style: IconButton.styleFrom(backgroundColor: _P.primary),
                          icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                        )
                      : const Icon(Icons.mic_none, color: _P.muted, key: ValueKey('mic')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.size = 44});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_indigo, _indigoDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Text(
        name.toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: size * 0.4, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return IconButton(icon: Icon(icon, color: _P.muted, size: 22), onPressed: () {});
  }
}

class _Msg {
  final DateTime ts;
  final String text;
  final bool mine;
  final bool read;
  _Msg(this.ts, this.text, this.mine, {this.read = false});
}
