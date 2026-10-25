import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'services/supabase.dart';
import 'models/profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: String.fromEnvironment('SUPABASE_URL',
        defaultValue: 'https://your-project.supabase.co'),
    publishableKey: String.fromEnvironment('SUPABASE_ANON_KEY',
        defaultValue: 'your-anon-key-here'),
  );
  runApp(const NYXApp());
}

const _indigo = Color(0xFF6366F1);
const _indigoDeep = Color(0xFF3B3E8F);
const _bg = Color(0xFF0E0F13);
const _surface = Color(0xFF17181D);
const _border = Color(0xFF26272E);
const _text = Color(0xFFE8EAED);
const _muted = Color(0xFF8A8C94);
const _success = Color(0xFF22C55E);

const _adaptiveBreakpoint = 600.0;

class _P {
  static const bg = _bg;
  static const surface = _surface;
  static const border = _border;
  static const text = _text;
  static const muted = _muted;
  static const primary = _indigo;
  static const success = _success;
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const AuthGate()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/conversations', builder: (_, __) => const ConversationListScreen()),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (_, state) => ChatScreen(conversationId: state.pathParameters['conversationId']!),
    ),
  ],
  redirect: (context, state) {
    final authed = Supa.currentUser != null;
    final loggingIn = state.matchedLocation == '/login';
    if (!authed && !loggingIn) return '/login';
    if (authed && loggingIn) return '/conversations';
    return null;
  },
);

class NYXApp extends StatelessWidget {
  const NYXApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NYX',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
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
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supa.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return _AuthErrorState(error: snapshot.error.toString());
        }
        final session = snapshot.data?.session;
        if (session != null) {
          return const ConversationListScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

class _AuthErrorState extends StatelessWidget {
  const _AuthErrorState({required this.error});
  final String error;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Connection Error', style: TextStyle(color: _P.text, fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: _P.muted, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => runApp(const NYXApp()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        if (_username.text.trim().isEmpty) throw 'Username required';
        await Supa.signUp(_email.text.trim(), _password.text, _username.text.trim());
      } else {
        await Supa.signIn(_email.text.trim(), _password.text);
      }
      if (mounted) context.go('/conversations');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_indigo, _indigoDeep],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text('N', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 24),
                Text(_isSignUp ? 'Create Account' : 'Welcome Back',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _P.text)),
                const SizedBox(height: 8),
                Text(_isSignUp ? 'Start messaging with NYX' : 'Sign in to continue',
                    style: const TextStyle(fontSize: 16, color: _P.muted)),
                const SizedBox(height: 32),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
                  ),
                if (_isSignUp) ...[
                  TextField(
                    controller: _username,
                    style: const TextStyle(color: _P.text),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle: TextStyle(color: _P.muted),
                      prefixIcon: Icon(Icons.person_outline, color: _P.muted),
                      filled: true,
                      fillColor: _P.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _P.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _P.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _P.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _email,
                  style: const TextStyle(color: _P.text),
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: _P.muted),
                    prefixIcon: Icon(Icons.email_outlined, color: _P.muted),
                    filled: true,
                    fillColor: _P.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _P.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _P.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _P.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  style: const TextStyle(color: _P.text),
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: _P.muted),
                    prefixIcon: Icon(Icons.lock_outline, color: _P.muted),
                    filled: true,
                    fillColor: _P.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _P.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _P.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _P.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _P.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isSignUp ? 'Create Account' : 'Sign In',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(_isSignUp
                      ? 'Already have an account? Sign In'
                      : 'Need an account? Sign Up',
                      style: TextStyle(color: _P.primary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});
  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _search = TextEditingController();
  List<Profile> _searchResults = [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _startDM(Profile other) async {
    final conv = await Supa.getOrCreateDM(other.id);
    if (mounted) context.go('/chat/${conv.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NYX', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supa.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > _adaptiveBreakpoint) {
            return _buildLargeScreenLayout(context);
          } else {
            return _buildSmallScreenLayout(context);
          }
        },
      ),
    );
  }

  Widget _buildSmallScreenLayout(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            style: const TextStyle(color: _P.text),
            decoration: InputDecoration(
              hintText: 'Search users...',
              hintStyle: TextStyle(color: _P.muted),
              prefixIcon: Icon(Icons.search, color: _P.muted),
              filled: true,
              fillColor: _P.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: _P.muted),
                      onPressed: () => _search.clear(),
                    )
                  : null,
            ),
            onChanged: (v) async {
              if (v.trim().isEmpty) {
                setState(() => _searchResults = []);
                return;
              }
              final results = await Supa.searchUsers(v.trim());
              if (mounted) setState(() => _searchResults = results);
            },
          ),
        ),
        if (_search.text.isNotEmpty && _searchResults.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Users', style: TextStyle(color: _P.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          ..._searchResults.map((u) => ListTile(
            leading: _Avatar(name: u.username[0].toUpperCase(), size: 44),
            title: Text(u.username, style: const TextStyle(color: _P.text)),
            subtitle: Text(u.displayName ?? '', style: TextStyle(color: _P.muted, fontSize: 13)),
            onTap: () => _startDM(u),
          ),),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Chats', style: TextStyle(color: _P.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              StreamBuilder<AuthState>(
                stream: Supa.authStateChanges,
                builder: (_, __) => Text(Supa.currentUser?.email ?? '',
                    style: TextStyle(color: _P.muted, fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Conversation>>(
            stream: Supa.watchConversations(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorState(message: 'Failed to load conversations', onRetry: () => setState(() {}));
              }
              final conversations = snapshot.data ?? [];
              if (conversations.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.forum_outlined, color: _P.muted, size: 56),
                      const SizedBox(height: 16),
                      Text('No chats yet', style: TextStyle(color: _P.muted, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Search a user above to start messaging', style: TextStyle(color: _P.muted, fontSize: 13)),
                    ],
                  ),
                );
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: conversations.length,
                    itemBuilder: (_, i) {
                      final conv = conversations[i];
                      final lastMsg = conv.messages?.isNotEmpty == true ? conv.messages!.last : null;
                      final unread = conv.unreadCount > 0;
                      return ListTile(
                        leading: _Avatar(name: conv.peerInitial, size: 44),
                        title: Text(
                          conv.peerLabel,
                          style: TextStyle(
                            color: _P.text,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        subtitle: lastMsg != null
                            ? Text(lastMsg.content, style: TextStyle(color: _P.muted, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (unread)
                              Container(
                                padding: const EdgeInsets.all(2),
                                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                decoration: const BoxDecoration(
                                  color: _P.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else if (lastMsg != null)
                              Text(DateFormat('h:mm a').format(lastMsg.createdAt), style: const TextStyle(color: _P.muted, fontSize: 11)),
                          ],
                        ),
                        onTap: () => context.go('/chat/${conv.id}'),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLargeScreenLayout(BuildContext context) {
    return Row(
      children: [
        const _NavSidebar(),
        Expanded(
          child: _buildSmallScreenLayout(context),
        ),
      ],
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _typing = false;
  Timer? _typingTimer;
  Profile? _peer;

  @override
  void initState() {
    super.initState();
    _loadPeer();
  }

  Future<void> _loadPeer() async {
    // Resolve the other participant of this DM so the header shows their
    // real identity instead of a hardcoded placeholder.
    final ids = await Supa.client
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', widget.conversationId)
        .not('user_id', 'eq', Supa.currentUser!.id)
        .limit(1);
    if (!mounted) return;
    final uid = (ids as List).cast<Map<String, dynamic>>().firstOrNull?['user_id'] as String?;
    if (uid == null) return;
    final profile = await Supa.getProfile(uid);
    if (mounted) setState(() => _peer = profile);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    _rollToBottom();
    await Supa.sendMessage(widget.conversationId, t);
  }

  void _markUnreadAsRead(List<Message> messages) {
    for (final m in messages) {
      if (m.senderId != Supa.currentUser!.id && m.readAt == null) {
        Supa.markRead(widget.conversationId, m.id);
      }
    }
  }

  void _onTypingChanged(String text) {
    if (text.isNotEmpty && !_typing) {
      setState(() => _typing = true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _typing = false);
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
            _MenuTile(icon: Icons.info_outline, label: 'About this chat', onTap: () => Navigator.pop(context)),
            _MenuTile(icon: Icons.block, label: 'Block ${_peer?.label ?? 'user'}', danger: true, onTap: () => Navigator.pop(context)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAttachSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuTile(icon: Icons.image_outlined, label: 'Photo or video', onTap: () => Navigator.pop(context)),
            _MenuTile(icon: Icons.insert_drive_file_outlined, label: 'Document', onTap: () => Navigator.pop(context)),
            _MenuTile(icon: Icons.camera_alt_outlined, label: 'Camera', onTap: () => Navigator.pop(context)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16, top: 2),
          child: _Avatar(name: _peer?.peerInitial ?? '?', size: 40),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _peer?.label ?? 'Chat',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _P.text),
            ),
            const Text('Active now', style: TextStyle(fontSize: 12, color: _P.muted)),
          ],
        ),
        actions: [
          _ActionBtn(Icons.videocam_rounded, onTap: () => _unsupported('Video calls coming soon')),
          _ActionBtn(Icons.phone_rounded, onTap: () => _unsupported('Voice calls coming soon')),
          _ActionBtn(Icons.more_vert, onTap: () => _showChatMenu(context)),
          const SizedBox(width: 8),
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
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<Message>>(
            stream: Supa.watchMessages(widget.conversationId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorState(message: 'Failed to load messages', onRetry: () {});
              }
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {});
                return const _EmptyState();
              }
              _markUnreadAsRead(messages);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _MessageRow(
                      msg: messages[i],
                      prev: i > 0 ? messages[i - 1] : null,
                      next: i + 1 < messages.length ? messages[i + 1] : null,
                      me: Supa.currentUser!.id,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_typing) const _TypingIndicator(),
        _Composer(controller: _ctrl, onSend: _send, onTypingChanged: _onTypingChanged, onAttach: () => _showAttachSheet(context)),
      ],
    );
  }

  Widget _buildLargeScreenChat(BuildContext context) {
    return Row(
      children: [
        const _NavSidebar(),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: Supa.watchMessages(widget.conversationId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _ErrorState(message: 'Failed to load messages', onRetry: () {});
                    }
                    final messages = snapshot.data ?? [];
                    if (messages.isEmpty) {
                      return const _EmptyState();
                    }
                    _markUnreadAsRead(messages);
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (_, i) => _MessageRow(
                            msg: messages[i],
                            prev: i > 0 ? messages[i - 1] : null,
                            next: i + 1 < messages.length ? messages[i + 1] : null,
                            me: Supa.currentUser!.id,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_typing) const _TypingIndicator(),
              _Composer(controller: _ctrl, onSend: _send, onTypingChanged: _onTypingChanged, onAttach: () => _showAttachSheet(context)),
            ],
          ),
        ),
      ],
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: _P.muted, size: 48),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: _P.text, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
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
        child: Text('Typing…', style: TextStyle(color: _P.muted, fontSize: 12, fontStyle: FontStyle.italic)),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.msg, this.prev, this.next, required this.me});
  final Message msg;
  final Message? prev;
  final Message? next;
  final String me;

  bool get _nowDateLine => prev == null || !_sameDay(prev!.createdAt, msg.createdAt);
  bool get _groupPrev => prev != null && prev!.senderId == msg.senderId && !_nowDateLine;
  bool get _groupNext => next != null && next!.senderId == msg.senderId && _sameDay(msg.createdAt, next!.createdAt);
  bool get mine => msg.senderId == me;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (_nowDateLine) _DateLine(ts: msg.createdAt),
        _Bubble(msg: msg, groupedTop: _groupPrev, groupedBottom: _groupNext, mine: mine),
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
  const _Bubble({required this.msg, this.groupedTop = false, this.groupedBottom = false, required this.mine});
  final Message msg;
  final bool groupedTop;
  final bool groupedBottom;
  final bool mine;

  @override
  Widget build(BuildContext context) {
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
            Text(msg.content, style: TextStyle(fontSize: 15, height: 1.3, color: mine ? Colors.white : _P.text)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmtTime(msg.createdAt), style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : _P.muted)),
                if (mine) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.readAt != null ? Icons.done_all : Icons.done,
                    size: 13,
                    color: msg.readAt != null ? _P.success : Colors.white70,
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
  const _Composer({required this.controller, required this.onSend, this.onTypingChanged, this.onAttach});
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String>? onTypingChanged;
  final VoidCallback? onAttach;

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
            IconButton(
              icon: const Icon(Icons.add_rounded, color: _P.muted, size: 22),
              onPressed: onAttach,
            ),
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
                onChanged: onTypingChanged,
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
                      : IconButton(
                          key: const ValueKey('mic'),
                          onPressed: onAttach,
                          icon: const Icon(Icons.mic_none, color: _P.muted),
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
  const _ActionBtn(this.icon, {this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return IconButton(icon: Icon(icon, color: _P.muted, size: 22), onPressed: onTap ?? () {});
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, this.danger = false, required this.onTap});
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: danger ? Colors.red : _P.muted, size: 22),
      title: Text(label, style: TextStyle(color: danger ? Colors.red : _P.text, fontSize: 15)),
      onTap: onTap,
    );
  }
}

class _NavSidebar extends StatelessWidget {
  const _NavSidebar();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: _P.surface,
        border: Border(right: BorderSide(color: _P.border, width: 1)),
      ),
      child: Column(children: [
        Container(
          width: 56, height: 56, margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_indigo, _indigoDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(child: Text('N', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white))),
        ),
        _NavItem(icon: Icons.forum_outlined, label: 'Chats', onTap: () => context.go('/conversations')),
        _NavItem(icon: Icons.search, label: 'Discover', onTap: () {}),
        _NavItem(icon: Icons.settings_outlined, label: 'Settings', onTap: () {}),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(Supa.currentUser?.email ?? '', style: const TextStyle(color: _P.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(icon, size: 22, color: _P.muted),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: _P.muted, fontSize: 15)),
        ]),
      )),
    );
  }
}
