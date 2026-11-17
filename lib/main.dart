import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide Presence; // app's services/presence.dart takes precedence
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/secure_screen.dart';
import 'services/app_lock.dart';
import 'services/app_update.dart';
import 'services/scheduled_messages.dart' as scheduled;
import 'services/voice_note.dart';
import 'screens/call_screen.dart';
import 'screens/circles_screen.dart';
import 'screens/lock_gate.dart';
import 'screens/status_composer.dart';
import 'screens/status_screen.dart';
import 'screens/status_viewer.dart';
import 'followers_following_screen.dart';
import 'widgets/home_nav_bar.dart';
import 'widgets/status_ring_avatar.dart';
import 'services/supabase.dart';
import 'services/presence.dart';
import 'services/push_notifications.dart';
import 'services/connection_monitor.dart';
import 'models/profile.dart';
import 'models/pending_message.dart';
import 'ui/states.dart';
import 'ui/errors.dart';
import 'app_constants.dart';
import 'theme/app_colors.dart' as app_colors;
export 'theme/app_colors.dart';
import 'screens/auth/auth_gate.dart' as auth_gate;
import 'screens/auth/login_screen.dart';
import 'screens/auth/confirmation_screen.dart';
import 'screens/navigation/nav_sidebar.dart';
import 'screens/chat/conversation_list_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/settings/account_settings_screen.dart';
import 'screens/chat/widgets/avatar.dart';


// Set the restart callback so auth_gate.dart can restart the app without importing BroApp
void _restartApp() {
  runApp(const BroApp());
}

// Initialize the callback early (called from main before runApp)
void _setupAuthGateCallback() {
  auth_gate.restartAppCallback = _restartApp;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init(
    (options) {
      options.dsn =
          'https://fd8f1fbe2d70d8f8dcd5d5434a361ab5@o4510827799707648.ingest.de.sentry.io/4512197248745552';
      options.tracesSampleRate = 1.0;
      options.debug = false;
    },
    appRunner: () async {
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
      _setupAuthGateCallback();
      runApp(const BroApp());
      unawaited(PushNotifications.initialize());
    },
  );
}




// Re-export color constants from theme for backward compatibility
const _bg = app_colors.bg;
const _surface = app_colors.surface;
const _surfaceHigh = app_colors.surfaceHigh;
const _surfaceLow = app_colors.surfaceLow;
const _border = app_colors.border;
const _text = app_colors.text;
const _muted = app_colors.muted;
const _success = app_colors.success;
const _volt = app_colors.volt;
const _darkOnVolt = app_colors.darkOnVolt;
const _adaptiveBreakpoint = app_colors.adaptiveBreakpoint;
const _chatBackgroundOptions = app_colors.chatBackgroundOptions;

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

final _rootNav = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNav,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const auth_gate.AuthGate()),
    GoRoute(path: '/circles', builder: (_, __) => const CirclesScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
        path: '/confirm',
        builder: (_, state) =>
            ConfirmationScreen(email: state.extra as String? ?? '')),
    GoRoute(
        path: '/conversations',
        builder: (_, __) => const ConversationListScreen()),
    GoRoute(path: '/status', builder: (_, __) => const StatusScreen()),
    GoRoute(
        path: '/status/new',
        builder: (_, state) => StatusComposerScreen(
              initialSource: state.uri.queryParameters['source'],
            )),
    GoRoute(
      path: '/status/view/:userId',
      builder: (_, state) => StatusViewerScreen(
        userId: state.pathParameters['userId']!,
        peerUserIds: switch (state.extra) {
          final List list => list.whereType<String>().toList(),
          _ => const <String>[],
        },
      ),
    ),
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
      builder: (_, state) => ChatScreen(
        conversationId: state.pathParameters['conversationId']!,
        initialPeer: state.extra is Profile ? state.extra as Profile : null,
      ),
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
  bool _appLocked = false;
  DateTime? _pausedAt;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectionMonitor.start();
    Presence.bind();
    _authSub = Supa.authStateChanges.listen((state) {
      if (state.session != null) {
        Presence.resume();
      } else {
        Presence.unbind();
      }
    });
    PushNotifications.setOpenHandler(
      (conversationId) => _router.go('/chat/$conversationId'),
    );
    AppLock.enabled.addListener(_onLockPref);
    unawaited(AppLock.bootstrap());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
  }

  void _onLockPref() {
    if (!mounted) return;
    if (AppLock.enabled.value) {
      setState(() => _appLocked = true);
    } else {
      setState(() => _appLocked = false);
    }
  }

  Future<void> _maybePromptUpdate() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final ctx = _rootNav.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await AppUpdate.promptIfNeeded(context: ctx, buildNumber: buildNumber);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    Presence.unbind();
    AppLock.enabled.removeListener(_onLockPref);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ConnectionMonitor.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Presence.resume();
      unawaited(_lockIfTimedOut());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      Presence.pause();
    }
  }

  Future<void> _lockIfTimedOut() async {
    if (!AppLock.enabled.value) return;
    final timeout = await AppLock.timeoutSeconds();
    final pausedAt = _pausedAt;
    final elapsed =
        pausedAt == null ? Duration.zero : DateTime.now().difference(pausedAt);
    if (elapsed >= Duration(seconds: timeout) && mounted) {
      setState(() => _appLocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MaterialApp.router(
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
        ),
        if (_appLocked)
          LockGate(
            title: 'BRO is locked',
            reason: 'Unlock BRO',
            onUnlocked: () {
              if (mounted) setState(() => _appLocked = false);
            },
          ),
      ],
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

