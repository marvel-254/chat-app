import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:local_auth/local_auth.dart';
import 'screens/call_screen.dart';
import 'followers_following_screen.dart';
import 'services/supabase.dart';
import 'services/push_notifications.dart';
import 'services/connection_monitor.dart';
import 'models/profile.dart';
import 'ui/states.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final uri = Uri.tryParse(supabaseUrl);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.host == 'your-project.supabase.co' || // stale placeholder build (#48)
      !const {'https', 'http'}.contains(uri.scheme) ||
      supabaseKey.isEmpty) {
    runApp(const BackendConfigurationApp());
    return;
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await Firebase.initializeApp();
  }
  runApp(const BroApp());
  unawaited(PushNotifications.initialize());
}

/// CI stamps every build with its release number via --dart-define
/// (build-apk.yml / pages.yml). Empty in local/debug builds.
const buildNumber = String.fromEnvironment('BUILD_NUMBER');

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

const _chatBackgroundOptions = <(String, String, List<Color>)>[
  ('default', 'Night', [_bg, _surfaceLow]),
  ('ocean', 'Ocean', [Color(0xFF102438), Color(0xFF0D1724)]),
  ('forest', 'Forest', [Color(0xFF142A24), Color(0xFF0E1B19)]),
  ('plum', 'Plum', [Color(0xFF2A1D35), Color(0xFF191521)]),
  ('ember', 'Ember', [Color(0xFF34221B), Color(0xFF1D1715)]),
];

BoxDecoration _chatCanvas(String name, {String? imageUrl}) {
  if (imageUrl != null) {
    return BoxDecoration(
        image: DecorationImage(
      image: NetworkImage(imageUrl),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(
          Colors.black.withValues(alpha: 0.28), BlendMode.darken),
    ));
  }
  final option = _chatBackgroundOptions.firstWhere((entry) => entry.$1 == name,
      orElse: () => _chatBackgroundOptions.first);
  return BoxDecoration(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: option.$3));
}

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
  static const volt = _volt;
  static const darkOnAccent = _darkOnVolt;
}

class BackendConfigurationApp extends StatelessWidget {
  const BackendConfigurationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BRO setup required',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: _P.bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_ethernet,
                      color: _P.primary, size: 48),
                  const SizedBox(height: 20),
                  const Text(
                    'BRO needs backend configuration',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _P.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Set SUPABASE_URL and SUPABASE_ANON_KEY for this build, then restart the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _P.muted, height: 1.5),
                  ),
                  if (buildNumber.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'build $buildNumber',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _P.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const AuthGate()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
        path: '/confirm',
        builder: (_, state) =>
            ConfirmationScreen(email: state.extra as String? ?? '')),
    GoRoute(
        path: '/conversations',
        builder: (_, __) => const ConversationListScreen()),
    GoRoute(
        path: '/settings', builder: (_, __) => const AccountSettingsScreen()),
    GoRoute(
        path: '/call/:conversationId',
        builder: (_, state) => CallScreen(
              conversationId: state.pathParameters['conversationId']!,
              peer: state.extra as Profile,
              callId: state.uri.queryParameters['id']!,
              video: state.uri.queryParameters['video'] == 'true',
              outgoing: state.uri.queryParameters['outgoing'] == 'true',
            )),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (_, state) =>
          ChatScreen(conversationId: state.pathParameters['conversationId']!),
    ),
    GoRoute(
      path: '/profile/:userId',
      builder: (_, state) => UserProfileScreen(
        userId: state.pathParameters['userId']!,
      ),
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

class BroApp extends StatefulWidget {
  const BroApp({super.key});

  @override
  State<BroApp> createState() => _BroAppState();
}

class _BroAppState extends State<BroApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectionMonitor.start();
    PushNotifications.setOpenHandler(
      (conversationId) => _router.go('/chat/$conversationId'),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ConnectionMonitor.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(Supa.recordLastSeen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BRO',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      routerConfig: _router,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (child != null) child,
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OfflineBanner(),
            ),
          ],
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _P.bg,
        colorScheme: ColorScheme.dark(
          primary: _P.primary,
          onPrimary: _P.darkOnAccent,
          surface: _P.surface,
          onSurface: _P.text,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _P.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
              color: _P.text, fontSize: 18, fontWeight: FontWeight.w600),
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
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
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
              Text('Connection Error',
                  style: TextStyle(
                      color: _P.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(error,
                  style: TextStyle(color: _P.muted, fontSize: 14),
                  textAlign: TextAlign.center),
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
        if (username.length < 3 ||
            !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
          throw 'Use at least 3 letters, numbers, dots, dashes, or underscores for your username.';
        }
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
      if (e is AuthApiException && e.code == 'email_not_confirmed') {
        // The account exists but the email hasn't been confirmed yet (#49).
        // Route to the confirmation screen (which can resend the email)
        // instead of surfacing a raw exception.
        if (mounted) context.go('/confirm', extra: _email.text.trim());
        return;
      }
      if (e is AuthRetryableFetchException) {
        if (mounted) {
          setState(() => _error =
              "Can't reach the server. Check your internet connection and try again.");
        }
        return;
      }
            if (e is AuthException) {
        // Server message is already human readable (e.g. "Invalid login
        // credentials"); never show the raw AuthApiException toString().
        if (mounted) setState(() => _error = e.message);
        return;
      }
      if (e is StateError) {
        if (mounted) setState(() => _error = e.message);
        return;
      }
      if (e is PostgrestException) {
        // Sign-up used to abort on the profiles INSERT (RLS 42501) and strand
        // the auth user (#43). The database trigger now creates the profile,
        // but keep a friendly recovery path if it ever fails again.
        if (mounted) {
          setState(() => _error =
              'Could not finish creating your account. Please try again.');
        }
        return;
      }
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
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
                            (
                              _isSignUp ? 'Create Account' : 'Create Account',
                              true
                            ),
                          ])
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isSignUp = entry.$2;
                                  _guideTarget =
                                      entry.$2 ? 'username' : 'email';
                                }),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: _isSignUp == entry.$2
                                        ? accent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(36),
                                    boxShadow: _isSignUp == entry.$2
                                        ? [
                                            BoxShadow(
                                                color: accent.withValues(
                                                    alpha: 0.3),
                                                blurRadius: 16)
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(entry.$1,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _isSignUp == entry.$2
                                              ? darkOnAccent
                                              : _P.muted,
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
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 13,
                                        height: 1.3))),
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
                        placeholder: 'alex_vance',
                        textInputAction: TextInputAction.next,
                        isGuideTarget: _guideTarget == 'username',
                        onFocus: () =>
                            setState(() => _guideTarget = 'username'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _AuthField(
                      controller: _email,
                      label: 'Email',
                      prefix: Icons.alternate_email_outlined,
                      placeholder: 'you@bro.network',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
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
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
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
                            boxShadow: [
                              BoxShadow(
                                  color: accent.withValues(alpha: 0.35),
                                  blurRadius: 22,
                                  spreadRadius: 1)
                            ],
                          ),
                          alignment: Alignment.center,
                          child: _loading
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: darkOnAccent),
                                )
                              : Text(_isSignUp ? 'Create Account' : 'Sign In',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: darkOnAccent,
                                      letterSpacing: 0.3)),
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
                            TextSpan(
                                text: _isSignUp
                                    ? 'Already in the crew? '
                                    : 'Need an account? ',
                                style: const TextStyle(color: _P.muted)),
                            TextSpan(
                                text: _isSignUp
                                    ? 'Sign In, Bro'
                                    : 'Claim Your Tag',
                                style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('By stepping in, you rep the Bro Code.',
                        style: TextStyle(fontSize: 11, color: _P.muted)),
                    if (buildNumber.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('BRO · build $buildNumber',
                          style:
                              const TextStyle(fontSize: 11, color: _P.muted)),
                    ],
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
                  label:
                      'BRO character waving and pointing toward the sign-in fields',
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
class _AuthField extends StatefulWidget {
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
    this.textInputAction,
    this.onSubmitted,
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
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<_AuthField> {
  late bool _obscured = widget.obscureText;

  @override
  void didUpdateWidget(covariant _AuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(widget.label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _P.muted,
                  letterSpacing: 0.08)),
        ),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: _P.surfaceLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: widget.isGuideTarget ? _P.primary : _P.border,
              width: widget.isGuideTarget ? 1.5 : 1,
            ),
            boxShadow: widget.isGuideTarget
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
            controller: widget.controller,
            obscureText: _obscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            onTap: widget.onFocus,
            style: const TextStyle(color: _P.text, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              prefixIcon: Icon(widget.prefix, color: _P.muted, size: 20),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              hintText: widget.placeholder,
              hintStyle: TextStyle(color: _P.muted.withValues(alpha: 0.6)),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: const BorderSide(color: _P.primary, width: 1.5),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
              suffixIcon: widget.obscureText
                  ? IconButton(
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: _P.muted,
                        size: 20,
                      ),
                      tooltip: _obscured ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _obscured = !_obscured),
                    )
                  : (widget.suffix != null
                      ? Icon(widget.suffix,
                          color: widget.suffixColor ?? _P.muted, size: 20)
                      : null),
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
                    child: Icon(Icons.mark_email_unread_outlined,
                        color: _P.primary, size: 40),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Check Your Email',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: _P.text)),
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
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_error!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 14)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _resending ? null : _resend,
                    icon: _resending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _P.text))
                        : const Icon(Icons.mark_email_read_outlined,
                            color: _P.text),
                    label: Text(_resending ? 'Sending…' : 'Resend Confirmation',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _P.text,
                      side: const BorderSide(color: _P.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Sign In',
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

String _formatConversationTimestamp(DateTime dt) {
  final now = DateTime.now();
  final local = dt.toLocal();
  if (now.year == local.year &&
      now.month == local.month &&
      now.day == local.day) {
    return DateFormat('h:mm a').format(local);
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == local.year &&
      yesterday.month == local.month &&
      yesterday.day == local.day) {
    return 'Yesterday';
  }
  if (now.difference(local).inDays < 7 && now.weekday != local.weekday) {
    return DateFormat('EEE').format(local);
  }
  if (now.year == local.year) {
    return DateFormat('MMM d').format(local);
  }
  return DateFormat('MM/dd/yy').format(local);
}

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});
  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final _search = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  Timer? _autoRefreshTimer;
  
  late final Future<List<Profile>> _suggestions = Supa.searchUsers('');
  List<Profile> _searchResults = [];
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  bool _searchLoading = false;
  bool _searchCompleted = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _autoRefresh();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final requestId = ++_searchRequestId;
    final query = value.trim();
    setState(() {
      _searchResults = [];
      _searchError = null;
      _searchLoading = false;
      _searchCompleted = false;
    });
    if (query.isEmpty) return;

    _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() => _searchLoading = true);
      try {
        final results = await Supa.searchUsers(query);
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchResults = results;
          _searchLoading = false;
          _searchCompleted = true;
        });
      } catch (_) {
        if (!mounted || requestId != _searchRequestId) return;
        setState(() {
          _searchError = 'Could not search users. Please try again.';
          _searchLoading = false;
          _searchCompleted = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchRequestId++;
    _autoRefreshTimer?.cancel();
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _startDM(Profile other) async {
    try {
      final conv = await Supa.getOrCreateDM(other.id);
      if (mounted) context.go('/chat/${conv.id}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Could not open this conversation. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/bro_logo.png',
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.flash_on, color: _P.primary, size: 24),
            ),
            const SizedBox(width: 10),
            const Text('BRO',
                style:
                    TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => context.push('/settings')),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await PushNotifications.unregisterCurrentToken();
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
            focusNode: _searchFocusNode,
            style: const TextStyle(color: _P.text),
            decoration: InputDecoration(
              hintText: 'Search users...',
              hintStyle: const TextStyle(color: _P.muted),
              prefixIcon: const Icon(Icons.search, color: _P.muted),
              filled: true,
              fillColor: _P.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: _P.muted),
                      onPressed: () {
                        _search.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        if (_search.text.trim().isNotEmpty && _searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_search.text.trim().isNotEmpty && _searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_searchError!,
                style: const TextStyle(color: Colors.redAccent)),
          ),
        if (_search.text.trim().isNotEmpty &&
            _searchCompleted &&
            _searchError == null &&
            _searchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No users found.', style: TextStyle(color: _P.muted)),
          ),
        if (_search.text.trim().isNotEmpty && _searchResults.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Users',
                style: TextStyle(
                    color: _P.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            height: (_searchResults.length * 72.0).clamp(72.0, 288.0),
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final u = _searchResults[index];
                return ListTile(
                  leading: GestureDetector(
                    onTap: () => context.push('/profile/${u.id}'),
                    child: _Avatar(
                        name: u.peerInitial, url: u.avatarUrl, size: 44),
                  ),
                  title: Text(u.label, style: const TextStyle(color: _P.text)),
                  subtitle: Text('@${u.username}',
                      style: TextStyle(color: _P.muted, fontSize: 13)),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_outline, size: 20),
                    color: _P.muted,
                    tooltip: 'View profile',
                    onPressed: () => context.push('/profile/${u.id}'),
                  ),
                  onTap: () => _startDM(u),
                );
              },
            ),
          ),
          const Divider(height: 1),
        ],
        if (_search.text.trim().isEmpty)
          FutureBuilder<List<Profile>>(
            future: _suggestions,
            builder: (context, snapshot) {
              final people = snapshot.data ?? const <Profile>[];
              if (people.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                      child: Text(
                        'People you may know',
                        style: TextStyle(
                          color: _P.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final user in people.take(8))
                            InkWell(
                              onTap: () => _startDM(user),
                              onLongPress: () =>
                                  context.push('/profile/${user.id}'),
                              child: SizedBox(
                                width: 80,
                                child: Column(
                                  children: [
                                    _Avatar(
                                      name: user.peerInitial,
                                      url: user.avatarUrl,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '@${user.username}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _P.text,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('Chats',
                  style: TextStyle(
                      color: _P.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
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
          child: RefreshIndicator(
            key: _refreshKey,
            onRefresh: _onRefresh,
            color: _P.primary,
            backgroundColor: _P.primary.withValues(alpha: 0.12),
            child: StreamBuilder<List<Conversation>>(
              stream: Supa.watchConversations(),
              builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _ErrorState(
                    message: 'Failed to load conversations',
                    onRetry: () => setState(() {}));
              }
              final conversations = snapshot.data ?? [];
              if (conversations.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: _P.surfaceHigh,
                            shape: BoxShape.circle,
                            border: Border.all(color: _P.border),
                          ),
                          child: const Center(
                            child: Icon(Icons.forum_outlined,
                                color: _P.primary, size: 36),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text('No chats yet',
                            style: TextStyle(
                                color: _P.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text(
                            'Search for users or pick from suggestions above to start messaging.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: _P.muted, fontSize: 13, height: 1.4)),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: () => _searchFocusNode.requestFocus(),
                          style: FilledButton.styleFrom(
                            backgroundColor: _P.surface,
                            foregroundColor: _P.primary,
                          ),
                          icon: const Icon(Icons.person_search_outlined,
                              size: 18),
                          label: const Text('Find someone',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
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
                      final lastMessage = conv.lastMessage;
                      final lastMessageAt = conv.lastMessageAt;
                      final unread = conv.unreadCount > 0;
                      return ListTile(
                        leading: GestureDetector(
                          onTap: conv.peerId != null
                              ? () => context.push('/profile/${conv.peerId}')
                              : null,
                          child: conv.peerId != null
                              ? FutureBuilder<bool>(
                                  future: Supa.isPeerOnline(conv.peerId!),
                                  builder: (_, snap) => _Avatar(
                                      name: conv.peerInitial,
                                      url: conv.peerAvatarUrl,
                                      size: 46,
                                      showOnlineDot: snap.data == true),
                                )
                              : _Avatar(
                                  name: conv.peerInitial,
                                  url: conv.peerAvatarUrl,
                                  size: 46),
                        ),
                        title: Text(
                          conv.peerLabel,
                          style: TextStyle(
                            color: _P.text,
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (conv.peerUsername != null)
                                Text('@${conv.peerUsername}',
                                    style: TextStyle(
                                        color: _P.muted.withValues(alpha: 0.8),
                                        fontSize: 11)),
                              if (lastMessage != null)
                                Text(
                                    lastMessage.startsWith('attachment:')
                                        ? '📎 Attachment'
                                        : lastMessage,
                                    style: TextStyle(
                                        color: unread ? _P.text : _P.muted,
                                        fontWeight: unread
                                            ? FontWeight.w500
                                            : FontWeight.normal,
                                        fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            ]),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (conv.isLocked)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Icon(Icons.lock_outline_rounded,
                                    size: 16, color: _P.muted),
                              ),
                            if (unread)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                constraints: const BoxConstraints(
                                    minWidth: 20, minHeight: 20),
                                decoration: BoxDecoration(
                                  color: _P.primary,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _P.primary.withValues(alpha: 0.35),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  conv.unreadCount > 99
                                      ? '99+'
                                      : '${conv.unreadCount}',
                                  style: const TextStyle(
                                      color: _P.darkOnAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else if (lastMessageAt != null)
                              Text(_formatConversationTimestamp(lastMessageAt),
                                  style: const TextStyle(
                                      color: _P.muted, fontSize: 11)),
                          ],
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        onTap: () => context.go('/chat/${conv.id}'),
                        onLongPress: conv.peerId != null
                            ? () => context.push('/profile/${conv.peerId}')
                            : null,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
      ],
    );
  }


  Future<void> _onRefresh() async {
    try {
      await Supa.refreshConversations();
    } catch (e) {
      debugPrint('Auto-refresh error: $e');
    }
  }

  void _autoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _refreshKey.currentState?.show();
    });
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
  bool _sendingMessage = false;
  Timer? _typingTimer;
  Profile? _peer;
  String? _peerTyping;
  Timer? _peerTypingTimer;
  RealtimeChannel? _callChannel;
  bool _incomingPrompt = false;
  String _chatBackground = 'default';
  String? _chatBackgroundImageUrl;
  Duration? _messageExpiry;
  bool _pinnedBannerDismissed = false;
  int _pinnedBannerIndex = 0;
  bool _peerIsOnline = false;
  StreamSubscription<String?>? _presenceSub;

  String _expiryLabel(Duration value) => switch (value.inDays) {
        1 => '24 hours',
        7 => '7 days',
        30 => '30 days',
        _ => '${value.inDays} days',
      };

  @override
  void initState() {
    super.initState();
    _loadPeer();
    _loadChatBackground();
    _loadMessageExpiry();
    Supa.onTyping(widget.conversationId, _onPeerTyping);
    _listenForCalls();
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
      _unsupported('Could not update the message timer.');
    }
  }

  Future<void> _authenticateAndLock() async {
    final auth = LocalAuthentication();
    final canCheck = await auth.canCheckBiometrics;
    final isAvailable = await auth.isDeviceSupported();
    if (!canCheck || !isAvailable) {
      _unsupported('Biometric authentication not available on this device.');
      return;
    }
    try {
      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Lock this conversation',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (didAuthenticate && mounted) {
        await Supa.setConversationLocked(widget.conversationId, true);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conversation locked'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Authentication failed'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _lockConversation() async {
    await _authenticateAndLock();
  }

  Future<void> _unlockConversation() async {
    final auth = LocalAuthentication();
    final canCheck = await auth.canCheckBiometrics;
    final isAvailable = await auth.isDeviceSupported();
    if (!canCheck || !isAvailable) {
      _unsupported('Biometric authentication not available on this device.');
      return;
    }
    try {
      final didAuthenticate = await auth.authenticate(
        localizedReason: 'Unlock this conversation',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (didAuthenticate && mounted) {
        await Supa.setConversationLocked(widget.conversationId, false);
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Conversation unlocked'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Authentication failed'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _loadChatBackground() async {
    final profile = await Supa.getProfile(Supa.currentUser!.id);
    if (profile == null) return;
    final imagePath = profile.chatBackgroundImagePath;
    final imageUrl = profile.chatBackground == 'custom' && imagePath != null
        ? await Supa.chatBackgroundUrl(imagePath)
        : null;
    if (mounted) {
      setState(() {
        _chatBackground = profile.chatBackground;
        _chatBackgroundImageUrl = imageUrl;
      });
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
    final uid = (ids as List)
        .cast<Map<String, dynamic>>()
        .firstOrNull?['user_id'] as String?;
    if (uid == null) return;
    final profile = await Supa.getProfile(uid);
    if (mounted) {
      setState(() => _peer = profile);
      _presenceSub?.cancel();
      _presenceSub = Supa.watchPeerPresence(uid).listen((presence) {
        if (mounted) setState(() => _peerIsOnline = presence == 'online');
      });
    }
  }

  @override
  void dispose() {
    Supa.unsubscribeTyping(widget.conversationId);
    _presenceSub?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _typingTimer?.cancel();
    _peerTypingTimer?.cancel();
    final callChannel = _callChannel;
    if (callChannel != null) Supa.client.removeChannel(callChannel);
    super.dispose();
  }

  Future<void> _send() async {
    final draft = _ctrl.text;
    final content = draft.trim();
    if (content.isEmpty || _sendingMessage) return;

    setState(() => _sendingMessage = true);
    Supa.broadcastTyping(widget.conversationId, false);
    _typingTimer?.cancel();
    setState(() => _typing = false);
    try {
      await Supa.sendMessage(widget.conversationId, content,
          expiry: _messageExpiry);
      if (!mounted) return;
      if (_ctrl.text == draft) _ctrl.clear();
      _rollToBottom();
    } catch (_) {
      if (mounted) {
        _unsupported('Message failed to send. Your draft is still here.');
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
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
                if (peer != null) context.push('/profile/${peer.id}');
              },
            ),
            _MenuTile(
              icon: Icons.lock_outlined,
              label: 'Lock conversation',
              onTap: () {
                Navigator.pop(context);
                _lockConversation();
              },
            ),
            _MenuTile(
              icon: Icons.lock_open_outlined,
              label: 'Unlock conversation',
              onTap: () {
                Navigator.pop(context);
                _unlockConversation();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showMessageActions(Message message) async {
    final isMine = message.senderId == Supa.currentUser!.id;
    final canEdit = isMine &&
        DateTime.now().difference(message.createdAt) <=
            const Duration(minutes: 15) &&
        !message.content.startsWith('attachment:');
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
    } catch (e) {
      if (e is StateError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ));
        }
      } else {
        _unsupported('Could not update this message.');
      }
    }
  }

  void _showAttachSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _P.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuTile(
              icon: Icons.image_outlined,
              label: 'Photo or video',
              onTap: () {
                Navigator.pop(context);
                _pickPhoto();
              },
            ),
            _MenuTile(
              icon: Icons.insert_drive_file_outlined,
              label: 'Document',
              onTap: () {
                Navigator.pop(context);
                _pickDocument();
              },
            ),
            _MenuTile(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(camera: true);
              },
            ),
            const SizedBox(height: 8),
          ],
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
    try {
      final attachment = await Supa.uploadAttachment(
          widget.conversationId, bytes, name, mimeType);
      await Supa.sendMessage(
          widget.conversationId, 'attachment:${jsonEncode(attachment)}');
      _rollToBottom();
    } catch (_) {
      _unsupported('Upload failed. Check your connection and try again.');
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
      _unsupported('Could not open the photo picker.');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;
      final file = files.first;
      final knownLength = file.lengthSync();
      if (knownLength != null && knownLength > 20 * 1024 * 1024) {
        _unsupported('Files must be 20 MB or smaller.');
        return;
      }
      final bytes = await file.readAsBytes();
      await _sendAttachment(bytes, file.name, _mimeType(file.name));
    } catch (_) {
      _unsupported('Could not open that document.');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                _Avatar(
                  name: _peer?.peerInitial ?? '?',
                  url: _peer?.avatarUrl,
                  size: 38,
                  showOnlineDot: _peerIsOnline,
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
                      if (_peerTyping != null)
                        Text(
                          'typing…',
                          style: const TextStyle(
                              fontSize: 12, color: _P.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else if (_peer != null)
                        StreamBuilder<String?>(
                          key: ValueKey(_peer!.id),
                          stream: Supa.watchPeerPresence(_peer!.id),
                          builder: (_, snap) {
                            final presence = snap.data;
                            final isOnline = presence == 'online';
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isOnline) ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: BoxDecoration(
                                      color: _P.success,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: _P.success
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                Flexible(
                                  child: Text(
                                    presence ?? '@${_peer!.username}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOnline ? _P.success : _P.muted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else
                        Text(
                          'Direct message',
                          style: TextStyle(fontSize: 12, color: _P.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
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
                      messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(
                        message: 'Failed to load messages',
                        onRetry: () => setState(() {}));
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
                  _markUnreadAsRead(messages);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        itemCount: messages.length,
                        itemBuilder: (_, i) => _MessageRow(
                          msg: messages[i],
                          prev: i > 0 ? messages[i - 1] : null,
                          next:
                              i + 1 < messages.length ? messages[i + 1] : null,
                          me: Supa.currentUser!.id,
                          onLongPress: _showMessageActions,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (_typing || _peerTyping != null)
              _TypingIndicator(
                label: _peerTyping != null
                    ? '${_peer?.label ?? 'Someone'} is typing…'
                    : 'Typing…',
              ),
            _Composer(
              controller: _ctrl,
              onSend: _send,
              onTypingChanged: _onTypingChanged,
              onAttach: () => _showAttachSheet(context),
              onVoice: () => _unsupported('Voice messages are coming soon.'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLargeScreenChat(BuildContext context) {
    return Row(
      children: [
        const _NavSidebar(),
        Expanded(
          child: StreamBuilder<List<Message>>(
            stream: Supa.watchMessages(widget.conversationId),
            builder: (context, snapshot) {
              final messages = snapshot.data ?? [];
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
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return _ErrorState(
                              message: 'Failed to load messages',
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
                        _markUnreadAsRead(messages);
                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              itemCount: messages.length,
                              itemBuilder: (_, i) => _MessageRow(
                                msg: messages[i],
                                prev: i > 0 ? messages[i - 1] : null,
                                next: i + 1 < messages.length
                                    ? messages[i + 1]
                                    : null,
                                me: Supa.currentUser!.id,
                                onLongPress: _showMessageActions,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (_typing || _peerTyping != null)
                    _TypingIndicator(
                      label: _peerTyping != null
                          ? '${_peer?.label ?? 'Someone'} is typing…'
                          : 'Typing…',
                    ),
                  _Composer(
                    controller: _ctrl,
                    onSend: _send,
                    onTypingChanged: _onTypingChanged,
                    onAttach: () => _showAttachSheet(context),
                    onVoice: () =>
                        _unsupported('Voice messages are coming soon.'),
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
            Text(message,
                style: const TextStyle(
                    color: _P.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
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
  const _TypingIndicator({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(label,
            style: const TextStyle(
                color: _P.muted, fontSize: 12, fontStyle: FontStyle.italic)),
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
      required this.onLongPress});
  final Message msg;
  final Message? prev;
  final Message? next;
  final String me;
  final ValueChanged<Message> onLongPress;

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
  Widget build(BuildContext context) {final counts = _counts;
    final uniqueEmojis = counts.keys.toList();
    final mutedColor = mine
        ? _P.darkOnAccent.withValues(alpha: 0.5)
        : _P.muted;
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
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 0.5),
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

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.msg,
      this.groupedTop = false,
      this.groupedBottom = false,
      required this.mine,
      required this.onLongPress});
  final Message msg;
  final bool groupedTop;
  final bool groupedBottom;
  final bool mine;
  final VoidCallback onLongPress;
  final ValueChanged<String>? onReactionTap = null;

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
              if (attachment != null)
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
                  onTap: onReactionTap,
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
                    Icon(
                      msg.readByPeer ? Icons.done_all : Icons.done,
                      size: 13,
                      color: msg.readByPeer
                          ? _P.success
                          : _P.darkOnAccent.withValues(alpha: 0.7),
                    ),
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
                          content: Text('Attachment is still unavailable.')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Could not load attachment'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(
              width: 180,
              height: 54,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
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
  });
  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String>? onTypingChanged;
  final VoidCallback? onAttach;
  final VoidCallback? onVoice;

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
                          style:
                              IconButton.styleFrom(backgroundColor: _P.primary),
                          icon: const Icon(Icons.arrow_upward_rounded,
                              color: _P.darkOnAccent),
                        )
                      : IconButton(
                          key: const ValueKey('mic'),
                          onPressed: onVoice,
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
  const _Avatar(
      {required this.name, this.size = 44, this.url, this.showOnlineDot = false});
  final String name;
  final double size;
  final String? url;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [_bg, _surfaceHigh],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: url == null || url!.isEmpty
          ? Text(name.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600))
          : ClipOval(
              child: Image.network(url!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(name.toUpperCase(),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: size * 0.4,
                              fontWeight: FontWeight.w600))))),
    );

    if (!showOnlineDot) return avatar;

    // Dot size scales with avatar: ~22% of avatar diameter, min 8, max 14.
    final dotSize = (size * 0.22).clamp(8.0, 14.0);
    final borderWidth = (dotSize * 0.22).clamp(1.5, 2.5);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: _P.success,
              shape: BoxShape.circle,
              border: Border.all(color: _P.bg, width: borderWidth),
              boxShadow: [
                BoxShadow(
                  color: _P.success.withValues(alpha: 0.45),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
        ),
      ],
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

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _about = TextEditingController();
  Profile? _profile;
  XFile? _avatarFile;
  String _chatBackground = 'default';
  String? _chatBackgroundImagePath;
  String? _chatBackgroundImageUrl;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _photoVisibility = 'everyone';
  String _statusVisibility = 'everyone';
  String _aboutVisibility = 'everyone';
  bool _readReceiptsEnabled = true;
  Duration? _defaultMessageExpiry;
  Duration? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await Supa.getProfile(Supa.currentUser!.id);
      if (!mounted) return;
      _profile = profile;
      _username.text = profile?.username ?? '';
      _displayName.text = profile?.displayName ?? '';
      _about.text = profile?.about ?? '';
      _photoVisibility = profile?.photoVisibility ?? 'everyone';
      _statusVisibility = profile?.statusVisibility ?? 'everyone';
      _aboutVisibility = profile?.aboutVisibility ?? 'everyone';
      _readReceiptsEnabled = profile?.readReceiptsEnabled ?? true;
      _defaultMessageExpiry = profile?.defaultMessageExpiry;
      _autoLockTimer = profile?.autoLockTimer;
      _chatBackground = profile?.chatBackground ?? 'default';
      _chatBackgroundImagePath = profile?.chatBackgroundImagePath;
      if (_chatBackgroundImagePath != null) {
        _chatBackgroundImageUrl =
            await Supa.chatBackgroundUrl(_chatBackgroundImagePath!);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your profile.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    final file = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (file != null && mounted) setState(() => _avatarFile = file);
  }

  Future<void> _pickChatBackground() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (file == null) return;
      final path =
          await Supa.uploadChatBackground(await file.readAsBytes(), file.name);
      final url = await Supa.chatBackgroundUrl(path);
      if (mounted) {
        setState(() {
          _error = null;
          _chatBackground = 'custom';
          _chatBackgroundImagePath = path;
          _chatBackgroundImageUrl = url;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not upload that image. Choose a JPEG, PNG, WebP, or GIF under 10 MB.');
      }
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.length < 3 ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
      setState(() => _error =
          'Use at least 3 letters, numbers, dots, dashes, or underscores for your username.');
      return;
    }
    if (_password.text.isNotEmpty && _password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supa.updateProfile(
          username: username, displayName: _displayName.text);
      await Supa.updateProfileDetails(
          about: _about.text,
          photoVisibility: _photoVisibility,
          statusVisibility: _statusVisibility,
          aboutVisibility: _aboutVisibility,
          readReceiptsEnabled: _readReceiptsEnabled,
          defaultMessageExpiry: _defaultMessageExpiry);
      await Supa.updateChatBackground(
        _chatBackground,
        imagePath:
            _chatBackground == 'custom' ? _chatBackgroundImagePath : null,
      );
      if (_avatarFile != null) {
        await Supa.uploadAvatar(
            await _avatarFile!.readAsBytes(), _avatarFile!.name);
      }
      if (_password.text.isNotEmpty) {
        await Supa.client.auth
            .updateUser(UserAttributes(password: _password.text));
      }
      _password.clear();
      _confirmPassword.clear();
      _avatarFile = null;
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not save changes. Check whether that username is already taken.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: const Text('Settings'),
            leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop())),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  Center(
                      child: Column(children: [
                    FutureBuilder<List<int>>(
                      future: _avatarFile?.readAsBytes(),
                      builder: (_, snap) => _avatarFile != null && snap.hasData
                          ? CircleAvatar(
                              radius: 48,
                              backgroundImage:
                                  MemoryImage(Uint8List.fromList(snap.data!)))
                          : _Avatar(
                              name: _profile?.peerInitial ?? '?',
                              url: _profile?.avatarUrl,
                              size: 96),
                    ),
                    TextButton.icon(
                        onPressed: _pickAvatar,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Change profile picture')),
                  ])),
                  const SizedBox(height: 16),
                  _SettingsField(
                      controller: _displayName,
                      label: 'Display name',
                      icon: Icons.badge_outlined),
                  const SizedBox(height: 14),
                  _SettingsField(
                      controller: _username,
                      label: 'Username',
                      icon: Icons.alternate_email),
                  const SizedBox(height: 14),
                  _SettingsField(
                      controller: _about,
                      label: 'About (max 160 characters)',
                      icon: Icons.info_outline),
                  const SizedBox(height: 20),
                  Text('Privacy',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  DropdownButtonFormField<String>(
                      initialValue: _photoVisibility,
                      decoration: const InputDecoration(
                          labelText: 'Profile photo visible to'),
                      items: const [
                        DropdownMenuItem(
                            value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(
                            value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'nobody', child: Text('Nobody'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _photoVisibility = v);
                      }),
                  DropdownButtonFormField<String>(
                      initialValue: _statusVisibility,
                      decoration: const InputDecoration(
                          labelText: 'Online status visible to'),
                      items: const [
                        DropdownMenuItem(
                            value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(
                            value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'nobody', child: Text('Nobody'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _statusVisibility = v);
                      }),
                  DropdownButtonFormField<String>(
                      initialValue: _aboutVisibility,
                      decoration:
                          const InputDecoration(labelText: 'About visible to'),
                      items: const [
                        DropdownMenuItem(
                            value: 'everyone', child: Text('Everyone')),
                        DropdownMenuItem(
                            value: 'contacts', child: Text('My contacts')),
                        DropdownMenuItem(value: 'nobody', child: Text('Nobody'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _aboutVisibility = v);
                      }),
                  const SizedBox(height: 20),
                  Text('Messages',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Read receipts'),
                    subtitle: Text(
                      'Let others know when you have read their messages',
                      style: TextStyle(color: _P.muted, fontSize: 12),
                    ),
                    value: _readReceiptsEnabled,
                    onChanged: (v) => setState(() => _readReceiptsEnabled = v),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Duration?>(
                    initialValue: _defaultMessageExpiry,
                    decoration: const InputDecoration(
                        labelText: 'Default message timer'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Off')),
                      DropdownMenuItem(
                          value: Duration(hours: 24), child: Text('24 hours')),
                      DropdownMenuItem(
                          value: Duration(days: 7), child: Text('7 days')),
                      DropdownMenuItem(
                          value: Duration(days: 30), child: Text('30 days')),
                    ],
                    onChanged: (v) => setState(() => _defaultMessageExpiry = v),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Duration?>(
                    initialValue: _autoLockTimer,
                    decoration: const InputDecoration(
                        labelText: 'Auto-lock conversations'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Off')),
                      DropdownMenuItem(
                          value: Duration(minutes: 1), child: Text('1 minute')),
                      DropdownMenuItem(
                          value: Duration(minutes: 5), child: Text('5 minutes')),
                      DropdownMenuItem(
                          value: Duration(minutes: 15), child: Text('15 minutes')),
                      DropdownMenuItem(
                          value: Duration(minutes: 30), child: Text('30 minutes')),
                      DropdownMenuItem(
                          value: Duration(hours: 1), child: Text('1 hour')),
                    ],
                    onChanged: (v) => setState(() => _autoLockTimer = v),
                  ),
                  const SizedBox(height: 24),
                  Text('Chat background',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (final option in _chatBackgroundOptions)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () =>
                            setState(() => _chatBackground = option.$1),
                        child: Container(
                          width: 112,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _P.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: _chatBackground == option.$1
                                    ? _P.primary
                                    : _P.border,
                                width: _chatBackground == option.$1 ? 2 : 1),
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: option.$3),
                                      borderRadius: BorderRadius.circular(8),
                                    )),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(option.$2,
                                        style: const TextStyle(
                                            color: _P.text,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                    if (_chatBackground == option.$1)
                                      const Icon(Icons.check_circle_rounded,
                                          color: _P.primary, size: 14),
                                  ],
                                ),
                              ]),
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _pickChatBackground,
                      child: Container(
                        width: 112,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _P.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _chatBackground == 'custom'
                                  ? _P.primary
                                  : _P.border,
                              width: _chatBackground == 'custom' ? 2 : 1),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _P.surfaceHigh,
                                  borderRadius: BorderRadius.circular(8),
                                  image: _chatBackgroundImageUrl == null
                                      ? null
                                      : DecorationImage(
                                          image: NetworkImage(
                                              _chatBackgroundImageUrl!),
                                          fit: BoxFit.cover),
                                ),
                                child: _chatBackgroundImageUrl == null
                                    ? const Center(
                                        child: Icon(
                                            Icons.add_photo_alternate_outlined,
                                            color: _P.muted))
                                    : null,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      _chatBackgroundImagePath == null
                                          ? 'Upload image'
                                          : 'My image',
                                      style: const TextStyle(
                                          color: _P.text,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500)),
                                  if (_chatBackground == 'custom')
                                    const Icon(Icons.check_circle_rounded,
                                        color: _P.primary, size: 14),
                                ],
                              ),
                            ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  Text('Change password',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  _SettingsField(
                      controller: _password,
                      label: 'New password',
                      icon: Icons.lock_outline,
                      obscure: true),
                  const SizedBox(height: 14),
                  _SettingsField(
                      controller: _confirmPassword,
                      label: 'Confirm new password',
                      icon: Icons.lock_outline,
                      obscure: true),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.redAccent))),
                  const SizedBox(height: 22),
                  FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _P.primary,
                        foregroundColor: _P.darkOnAccent,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _P.darkOnAccent))
                          : const Text('Save changes')),
                  const SizedBox(height: 12),
                  Center(
                      child: Text(Supa.currentUser?.email ?? '',
                          style: TextStyle(color: _P.muted, fontSize: 12))),
                  const SizedBox(height: 28),
                  Text('About',
                      style: TextStyle(
                          color: _P.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                      buildNumber.isEmpty
                          ? 'BRO · development build'
                          : 'BRO · build $buildNumber',
                      style:
                          const TextStyle(color: _P.muted, fontSize: 12)),
                ]),
              )),
      );
}

class _SettingsField extends StatefulWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;

  @override
  State<_SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<_SettingsField> {
  late bool _obscured = widget.obscure;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _obscured,
        style: const TextStyle(color: _P.text),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(color: _P.muted),
          prefixIcon: Icon(widget.icon, color: _P.muted),
          suffixIcon: widget.obscure
              ? IconButton(
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: _P.muted,
                  ),
                  tooltip: _obscured ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
          filled: true,
          fillColor: _P.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _P.primary, width: 1.5)),
        ),
      );
}

// ---------------------------------------------------------------------------
// User Profile Screen
// ---------------------------------------------------------------------------

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Profile? _profile;
  bool _loading = true;
  bool _isFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _followLoading = false;
  String? _error;

  bool get _isSelf => Supa.currentUser?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        Supa.getProfile(widget.userId),
        if (!_isSelf) Supa.isFollowing(widget.userId),
        Supa.getFollowersCount(widget.userId),
        Supa.getFollowingCount(widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as Profile?;
        if (!_isSelf) _isFollowing = results[1] as bool;
        _followersCount = results[_isSelf ? 1 : 2] as int;
        _followingCount = results[_isSelf ? 2 : 3] as int;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load profile.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _followLoading = true);
    try {
      final newFollow = !_isFollowing;
      await Supa.setFollowing(widget.userId, newFollow);
      if (!mounted) return;
      setState(() {
        _isFollowing = newFollow;
        _followersCount += newFollow ? 1 : -1;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update follow status. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _openDM() async {
    try {
      final conv = await Supa.getOrCreateDM(widget.userId);
      if (mounted) context.go('/chat/${conv.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open conversation.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showFollowersSheet({required bool startOnFollowing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FollowersFollowingScreen(
          userId: widget.userId,
          initialTab: startOnFollowing ? 1 : 0,
          onOpenProfile: (uid) => context.push('/profile/$uid'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _P.bg,
      appBar: AppBar(
        backgroundColor: _P.bg,
        elevation: 0,
        leading: const BackButton(color: _P.text),
        title: _profile == null
            ? null
            : Text(
                _profile!.label,
                style: const TextStyle(
                    color: _P.text, fontWeight: FontWeight.w700, fontSize: 17),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off_outlined,
                          size: 48, color: _P.muted),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: _P.muted, fontSize: 15)),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final profile = _profile!;
    final isMe = _isSelf;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Avatar & name ──────────────────────────────────────────────
          const SizedBox(height: 28),
          Center(
            child: Stack(
              children: [
                _Avatar(
                  name: profile.peerInitial,
                  url: profile.avatarUrl,
                  size: 92,
                ),
                // Subtle glow ring
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _P.primary.withValues(alpha: 0.35),
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            profile.label,
            style: const TextStyle(
                color: _P.text, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '@${profile.username}',
            style: TextStyle(color: _P.muted, fontSize: 14),
          ),
          // Last seen / online indicator
          if (!isMe) ...[
            const SizedBox(height: 6),
            StreamBuilder<String?>(
              stream: Supa.watchPeerPresence(profile.id),
              builder: (_, snap) {
                final presence = snap.data;
                if (presence == null) return const SizedBox.shrink();
                final isOnline = presence == 'online';
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: isOnline ? _P.success : _P.muted,
                        shape: BoxShape.circle,
                        boxShadow: isOnline
                            ? [
                                BoxShadow(
                                  color: _P.success.withValues(alpha: 0.5),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    Text(
                      presence,
                      style: TextStyle(
                        color: isOnline ? _P.success : _P.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 20),

          // ── Follower / following counts ─────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ProfileStatChip(
                label: 'Followers',
                count: _followersCount,
                onTap: () => _showFollowersSheet(startOnFollowing: false),
              ),
              const SizedBox(width: 24),
              _ProfileStatChip(
                label: 'Following',
                count: _followingCount,
                onTap: () => _showFollowersSheet(startOnFollowing: true),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Action buttons (only for other users) ───────────────────────
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _isFollowing ? _P.surfaceHigh : _P.primary,
                        foregroundColor:
                            _isFollowing ? _P.text : _P.darkOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _followLoading ? null : _toggleFollow,
                      icon: _followLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _isFollowing ? _P.text : _P.darkOnAccent,
                              ),
                            )
                          : Icon(
                              _isFollowing
                                  ? Icons.person_remove_outlined
                                  : Icons.person_add_outlined,
                              size: 18,
                            ),
                      label: Text(
                        _isFollowing ? 'Unfollow' : 'Follow',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _P.text,
                        side: const BorderSide(color: _P.border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _openDM,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Message',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ] else ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit profile'),
              style: TextButton.styleFrom(foregroundColor: _P.primary),
            ),
            const SizedBox(height: 28),
          ],

          // ── About section ──────────────────────────────────────────────
          if (profile.about != null && profile.about!.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'About',
                  style: TextStyle(
                    color: _P.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _P.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _P.border.withValues(alpha: 0.5)),
              ),
              width: double.infinity,
              child: Text(
                profile.about!.trim(),
                style: TextStyle(
                    color: _P.text.withValues(alpha: 0.9),
                    fontSize: 14,
                    height: 1.5),
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── Joined date ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 13, color: _P.muted.withValues(alpha: 0.6)),
                const SizedBox(width: 6),
                Text(
                  'Joined ${_fmtJoined(profile.createdAt)}',
                  style: TextStyle(
                      color: _P.muted.withValues(alpha: 0.6), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  static String _fmtJoined(DateTime dt) {
    const months = [
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
    return '${months[dt.month - 1]} ${dt.year}';
  }
}

// Small tappable stat chip used in the profile page
class _ProfileStatChip extends StatelessWidget {
  const _ProfileStatChip(
      {required this.label, required this.count, required this.onTap});
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _fmt(count),
            style: const TextStyle(
                color: _P.text, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: _P.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ---------------------------------------------------------------------------
// Followers / Following Sheet
// ---------------------------------------------------------------------------

class _FollowersFollowingSheet extends StatefulWidget {
  const _FollowersFollowingSheet({
    required this.userId,
    required this.onOpenProfile,
  });
  final String userId;
  final void Function(String userId) onOpenProfile;

  @override
  State<_FollowersFollowingSheet> createState() =>
      _FollowersFollowingSheetState();
}

class _FollowersFollowingSheetState extends State<_FollowersFollowingSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Profile>? _followers;
  List<Profile>? _following;
  bool _loadingFollowers = true;
  bool _loadingFollowing = true;

  @override
  void initState() {
    super.initState();
    _tabs =
        TabController(length: 2, vsync: this, initialIndex: 0);
    _loadFollowers();
    _loadFollowing();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadFollowers() async {
    try {
      final list = await Supa.getFollowers(widget.userId);
      if (mounted) {
        setState(() {
          _followers = list;
          _loadingFollowers = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _followers = [];
          _loadingFollowers = false;
        });
      }
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final list = await Supa.getFollowing(widget.userId);
      if (mounted) {
        setState(() {
          _following = list;
          _loadingFollowing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _following = [];
          _loadingFollowing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: _P.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabs,
            labelColor: _P.primary,
            unselectedLabelColor: _P.muted,
            indicatorColor: _P.primary,
            indicatorWeight: 2.5,
            labelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            tabs: [
              Tab(
                text: 'Followers'
                    '${_followers != null ? '  ${_fmt(_followers!.length)}' : ''}',
              ),
              Tab(
                text: 'Following'
                    '${_following != null ? '  ${_fmt(_following!.length)}' : ''}',
              ),
            ],
          ),
          const Divider(height: 1, color: _P.border),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildList(_followers, _loadingFollowers, scrollCtrl),
                _buildList(_following, _loadingFollowing, scrollCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
      List<Profile>? profiles, bool loading, ScrollController scrollCtrl) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (profiles == null || profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 44, color: _P.muted),
            const SizedBox(height: 10),
            Text('Nobody here yet',
                style: TextStyle(color: _P.muted, fontSize: 14)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: profiles.length,
      itemBuilder: (_, i) {
        final p = profiles[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: _Avatar(name: p.peerInitial, url: p.avatarUrl, size: 42),
          title: Text(p.label,
              style:
                  const TextStyle(color: _P.text, fontWeight: FontWeight.w600)),
          subtitle: Text('@${p.username}',
              style: TextStyle(color: _P.muted, fontSize: 12)),
          trailing: p.id == Supa.currentUser?.id
              ? null
              : _FollowToggleButton(userId: p.id),
          onTap: () => widget.onOpenProfile(p.id),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        );
      },
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

/// A small follow/unfollow toggle button used inside list tiles.
class _FollowToggleButton extends StatefulWidget {
  const _FollowToggleButton({required this.userId});
  final String userId;

  @override
  State<_FollowToggleButton> createState() => _FollowToggleButtonState();
}

class _FollowToggleButtonState extends State<_FollowToggleButton> {
  bool? _following; // null = loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Supa.isFollowing(widget.userId).then((v) {
      if (mounted) setState(() => _following = v);
    }).catchError((_) {
      if (mounted) setState(() => _following = false);
    });
  }

  Future<void> _toggle() async {
    final current = _following;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    try {
      await Supa.setFollowing(widget.userId, !current);
      if (mounted) setState(() => _following = !current);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_following == null) {
      return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _busy
          ? const SizedBox(
              key: ValueKey('busy'),
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: _P.primary))
          : OutlinedButton(
              key: ValueKey(_following),
              onPressed: _toggle,
              style: OutlinedButton.styleFrom(
                foregroundColor: _following! ? _P.muted : _P.primary,
                side: BorderSide(
                    color: _following! ? _P.border : _P.primary, width: 1.2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(80, 32),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_following! ? 'Following' : 'Follow'),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned Messages Banner
// ---------------------------------------------------------------------------

/// A compact banner shown at the top of the chat when at least one message is
/// pinned.  Tapping it cycles through pinned messages and scrolls to each one
/// in the list.  Long-pressing opens a full sheet of all pinned messages.
/// The × button hides the banner for the current session (without unpinning).
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
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _P.muted))
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
        Image.asset('assets/images/bro_logo.png',
            width: 56, height: 56, gaplessPlayback: true),
        _NavItem(
            icon: Icons.forum_outlined,
            label: 'Chats',
            onTap: () => context.go('/conversations')),
        _NavItem(icon: Icons.search, label: 'Discover', onTap: () {}),
        _NavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.go('/settings')),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(Supa.currentUser?.email ?? '',
              style: const TextStyle(color: _P.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap,
          child: Padding(
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
