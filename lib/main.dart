import 'dart:async';
import 'package:flutter/foundation.dart';
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
  runApp(const BroApp());
}

const _bg = Color(0xFF121318);
const _surface = Color(0xFF1E1F25);
const _surfaceHigh = Color(0xFF292A2F);
const _surfaceLow = Color(0xFF0D0E13);
const _border = Color(0xFF444932);
const _text = Color(0xFFE3E1E9);
const _muted = Color(0xFFC5C9AC);
const _success = Color(0xFF22C55E);

// Electric Street accents
const _volt = Color(0xFFD4FF00); // primary accent (lime)
const _darkOnVolt = Color(0xFF0C0D12); // text on lime accents

const _adaptiveBreakpoint = 600.0;

class _P {
  static const bg = _bg;
  static const surface = _surface;
  static const surfaceHigh = _surfaceHigh;
  static const surfaceLow = _surfaceLow;
  static const border = _border;
  static const text = _text;
  static const muted = _muted;
  static const success = _success;
  static const primary = _volt;
  static const darkOnAccent = _darkOnVolt;
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const AuthGate()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/confirm', builder: (_, state) => ConfirmationScreen(email: state.extra as String? ?? '')),
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

class BroApp extends StatelessWidget {
  const BroApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BRO',
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
          titleTextStyle: TextStyle(color: _P.text, fontSize: 18, fontWeight: FontWeight.w600),
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
                onPressed: () => runApp(const BroApp()),
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
  String _guideTarget = 'email';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (!email.contains('@') || !email.contains('.')) {
        throw 'Enter a valid email address';
      }
      if (password.length < 6) {
        throw 'Password must be at least 6 characters';
      }
      if (_isSignUp) {
        final username = _username.text.trim();
        if (username.isEmpty) throw 'Username required';
        final res = await Supa.signUp(email, password, username);
        // Supabase may require email confirmation before sign-in is allowed.
        // If no session was created, the user must confirm their email first.
        if (res.session == null) {
          if (mounted) {
            context.go('/confirm', extra: email);
          }
          return;
        }
      } else {
        await Supa.signIn(email, password);
      }
      if (mounted) {
        context.go('/conversations');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _P.primary;
    final darkOnAccent = _P.darkOnAccent;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: _bg),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WelcomeHero(isSignUp: _isSignUp),
                    const SizedBox(height: 28),

                    // Segmented Sign In / Create toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _P.surfaceLow,
                        borderRadius: BorderRadius.circular(40),
                        border: Border.all(color: _P.border, width: 1),
                      ),
                      child: Row(
                        children: [
                          for (final entry in [
                            (_isSignUp ? 'Sign In' : 'Sign In', false),
                            (_isSignUp ? 'Create Account' : 'Create Account', true),
                          ])
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isSignUp = entry.$2;
                                  _guideTarget = entry.$2 ? 'username' : 'email';
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _isSignUp == entry.$2
                                        ? accent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(36),
                                    boxShadow: _isSignUp == entry.$2
                                        ? [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 16)]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(entry.$1,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _isSignUp == entry.$2 ? darkOnAccent : _P.muted,
                                        )),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error banner
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13, height: 1.3))),
                          ],
                        ),
                      ),

                    // Fields
                    if (_isSignUp) ...[
                      _AuthField(
                        controller: _username,
                        label: 'What They Call You',
                        prefix: Icons.badge_outlined,
                        suffix: Icons.check_circle,
                        suffixColor: accent,
                        placeholder: 'Alex Vance',
                        isGuideTarget: _guideTarget == 'username',
                        onFocus: () => setState(() => _guideTarget = 'username'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _AuthField(
                      controller: _email,
                      label: 'Email',
                      prefix: Icons.alternate_email_outlined,
                      placeholder: 'you@bro.network',
                      keyboardType: TextInputType.emailAddress,
                      isGuideTarget: _guideTarget == 'email',
                      onFocus: () => setState(() => _guideTarget = 'email'),
                    ),
                    const SizedBox(height: 16),
                    _AuthField(
                      controller: _password,
                      label: 'Secret Code',
                      prefix: Icons.lock_outline,
                      placeholder: '••••••••',
                      obscureText: true,
                      isGuideTarget: _guideTarget == 'password',
                      onFocus: () => setState(() => _guideTarget = 'password'),
                    ),
                    const SizedBox(height: 24),

                    // CTA
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: GestureDetector(
                        onTap: _loading ? null : _submit,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 22, spreadRadius: 1)],
                          ),
                          alignment: Alignment.center,
                          child: _loading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: darkOnAccent),
                                )
                              : Text(_isSignUp ? 'Create Account' : 'Sign In',
                                  style: TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700, color: darkOnAccent, letterSpacing: 0.3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _guideTarget = _isSignUp ? 'username' : 'email';
                      }),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 14, color: _P.muted),
                          children: [
                            TextSpan(text: _isSignUp ? 'Already in the crew? ' : 'Need an account? ',
                                style: const TextStyle(color: _P.muted)),
                            TextSpan(text: _isSignUp ? 'Sign In, Bro' : 'Claim Your Tag',
                                style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('By stepping in, you rep the Bro Code. E2E Encrypted.',
                        style: TextStyle(fontSize: 11, color: _P.muted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-body welcome artwork alongside the sign-in copy.
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero({required this.isSignUp});
  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 312,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;
          final avatarWidth = compact ? 108.0 : 132.0;
          final gap = compact ? 8.0 : 12.0;
          final headingSize = compact ? 22.0 : 25.0;
          final taglineSize = compact ? 12.5 : 14.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: avatarWidth,
                height: 300,
                child: Semantics(
                  image: true,
                  label: 'BRO character waving and pointing toward the sign-in fields',
                  child: Image.asset(
                    'assets/images/welcome_avatar_fullbody.png',
                    width: avatarWidth,
                    height: 300,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isSignUp
                          ? 'Your people. Your place.'
                          : 'Good to see you, Bro.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: headingSize,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: _P.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isSignUp
                          ? 'Make a space for the conversations that matter.'
                          : 'All your convos, right here.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: taglineSize,
                        height: 1.35,
                        color: _P.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pill-shaped auth input matching the Electric Street design.
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.prefix,
    required this.placeholder,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.suffixColor,
    this.isGuideTarget = false,
    this.onFocus,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefix;
  final String placeholder;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? suffix;
  final Color? suffixColor;
  final bool isGuideTarget;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _P.muted, letterSpacing: 0.08)),
        ),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: _P.surfaceLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isGuideTarget ? _P.primary : _P.border,
              width: isGuideTarget ? 1.5 : 1,
            ),
            boxShadow: isGuideTarget
                ? [
                    BoxShadow(
                      color: _P.primary.withValues(alpha: 0.12),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            onTap: onFocus,
            style: const TextStyle(color: _P.text, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              prefixIcon: Icon(prefix, color: _P.muted, size: 20),
              prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              hintText: placeholder,
              hintStyle: TextStyle(color: _P.muted.withValues(alpha: 0.6)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(color: _P.primary, width: 1.5),
              ),
              suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              suffixIcon: suffix != null
                  ? Icon(suffix, color: suffixColor ?? _P.muted, size: 20)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class ConfirmationScreen extends StatefulWidget {
  const ConfirmationScreen({super.key, required this.email});
  final String email;

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  bool _resending = false;
  String? _error;

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await Supa.resendConfirmation(widget.email);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _resending = false);
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
                    color: _P.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _P.border),
                  ),
                  child: const Center(
                    child: Icon(Icons.mark_email_unread_outlined, color: _P.primary, size: 40),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Check Your Email',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: _P.text)),
                const SizedBox(height: 8),
                Text(
                  'We sent a confirmation link to\n${widget.email}. Click it to activate your account, then sign in.',
                  style: const TextStyle(fontSize: 15, color: _P.muted),
                  textAlign: TextAlign.center,
                ),
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
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _resending ? null : _resend,
                    icon: _resending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _P.text))
                        : const Icon(Icons.mark_email_read_outlined, color: _P.text),
                    label: Text(_resending ? 'Sending…' : 'Resend Confirmation',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _P.text,
                      side: const BorderSide(color: _P.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Sign In', style: TextStyle(color: _P.primary)),
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
        title: const Text('BRO', style: TextStyle(fontWeight: FontWeight.w600)),
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
  String? _peerTyping;
  Timer? _peerTypingTimer;

  @override
  void initState() {
    super.initState();
    _loadPeer();
    Supa.onTyping(widget.conversationId, _onPeerTyping);
  }

  void _onPeerTyping(String userId, bool isTyping) {
    if (userId == Supa.currentUser!.id) return; // ignore own broadcasts
    if (isTyping) {
      setState(() => _peerTyping = userId);
      _peerTypingTimer?.cancel();
      _peerTypingTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _peerTyping = null);
      });
    } else {
      if (mounted && _peerTyping == userId) setState(() => _peerTyping = null);
    }
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
    Supa.unsubscribeTyping(widget.conversationId);
    _ctrl.dispose();
    _scroll.dispose();
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    super.dispose();
  }

  void _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    Supa.broadcastTyping(widget.conversationId, false);
    _typingTimer?.cancel();
    if (mounted) setState(() => _typing = false);
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
      Supa.broadcastTyping(widget.conversationId, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _typing = false);
        Supa.broadcastTyping(widget.conversationId, false);
      }
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
            const _OnlineStatus(),
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
        if (_typing || _peerTyping != null)
          _TypingIndicator(
            label: _peerTyping != null ? '${_peer?.label ?? 'Someone'} is typing…' : 'Typing…',
          ),
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
              if (_typing || _peerTyping != null)
                _TypingIndicator(
                  label: _peerTyping != null ? '${_peer?.label ?? 'Someone'} is typing…' : 'Typing…',
                ),
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

class _OnlineStatus extends StatefulWidget {
  const _OnlineStatus();

  @override
  State<_OnlineStatus> createState() => _OnlineStatusState();
}

class _OnlineStatusState extends State<_OnlineStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final glow = 0.2 + _pulse.value * 0.45;
            return Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _P.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _P.success.withValues(alpha: glow),
                    blurRadius: 3 + _pulse.value * 5,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        const Text('Active now',
            style: TextStyle(fontSize: 12, color: _P.muted)),
      ],
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: const TextStyle(color: _P.muted, fontSize: 12, fontStyle: FontStyle.italic)),
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
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
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
            Text(msg.content, style: TextStyle(fontSize: 15, height: 1.3, color: mine ? _P.darkOnAccent : _P.text)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmtTime(msg.createdAt), style: TextStyle(fontSize: 11, color: mine ? _P.darkOnAccent.withValues(alpha: 0.7) : _P.muted)),
                if (mine) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.readAt != null ? Icons.done_all : Icons.done,
                    size: 13,
                    color: msg.readAt != null ? _P.success : _P.darkOnAccent.withValues(alpha: 0.7),
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
                          icon: const Icon(Icons.arrow_upward_rounded, color: _P.darkOnAccent),
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
        gradient: const LinearGradient(colors: [_bg, _surfaceHigh], begin: Alignment.topLeft, end: Alignment.bottomRight),
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
        Image.asset('assets/images/bro_logo.png', width: 56, height: 56, gaplessPlayback: true),
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
