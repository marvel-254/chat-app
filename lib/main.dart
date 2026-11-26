import 'dart:async';
import 'package:flutter/material.dart';
import 'services/call_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide Presence; // app's services/presence.dart takes precedence
import 'package:go_router/go_router.dart';
import 'services/app_lock.dart';
import 'services/app_update.dart';
import 'screens/call_screen.dart';
import 'screens/recent_calls_screen.dart';
import 'services/calls.dart';
import 'services/legacy_messaging.dart';
import 'models/call_record.dart';
import 'services/push_message_target.dart';
import 'screens/circles_screen.dart';
import 'screens/lock_gate.dart';
import 'screens/status_composer.dart';
import 'screens/status_screen.dart';
import 'screens/status_viewer.dart';
import 'services/supabase.dart';
import 'services/presence.dart';
import 'services/push_notifications.dart';
import 'services/connection_monitor.dart';
import 'models/profile.dart';
import 'ui/states.dart';
import 'app_constants.dart';
import 'theme/app_colors.dart' as app_colors;
export 'theme/app_colors.dart';
import 'screens/auth/auth_gate.dart' as auth_gate;
import 'screens/auth/login_screen.dart';
import 'screens/auth/mfa_challenge_screen.dart';
import 'screens/auth/onboarding_screen.dart' as onboarding;
import 'screens/auth/confirmation_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/chat/conversation_list_screen.dart';
import 'screens/chat/suggest_friends_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/settings/account_settings_screen.dart';
import 'screens/settings/notification_settings_screen.dart';
import 'screens/settings/close_friends_screen.dart';
import 'screens/settings/digital_avatar_screen.dart';
import 'screens/settings/friendship_timeline_screen.dart';
import 'screens/settings/linked_devices_screen.dart';

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

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final uri = Uri.tryParse(supabaseUrl);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.host == 'your-project.supabase.co' ||
      !const {'https', 'http'}.contains(uri.scheme) ||
      supabaseKey.isEmpty) {
    runApp(const BackendConfigurationApp());
    return;
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  await onboarding.loadOnboardingStatus();
  _setupAuthGateCallback();
  final launchUri = Uri.base;
  runApp(const BroApp());

  // Neither service is required for the first frame; start them after paint.
  unawaited(_initializeSentry());
  unawaited(_initializePush(launchUri));
}

Future<void> _initializeSentry() async {
  try {
    await SentryFlutter.init(
      (options) {
        options.dsn =
            'https://fd8f1fbe2d70d8f8dcd5d5434a361ab5@o4510827799707648.ingest.de.sentry.io/4512197248745552';
        options.environment = kReleaseMode ? 'production' : 'development';
        options.release = const String.fromEnvironment(
          'APP_RELEASE',
          defaultValue: 'bro@dev',
        );
        options.dist = buildNumber.isEmpty ? null : buildNumber;
        options.sendDefaultPii = false;
        options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
        options.debug = false;
      },
    );
  } catch (e) {
    debugPrint('Sentry could not start: $e');
  }
}

Future<void> _initializePush(Uri launchUri) async {
  try {
    await PushNotifications.initialize(launchUri: launchUri);
  } catch (_) {
    debugPrint('Notifications could not start. Chat is still available.');
  }
}

class _P {
  static const bg = app_colors.bg;
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const primary = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _P.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.settings_ethernet_rounded,
                      color: _P.primary,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Backend Not Configured',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _P.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This APK was built without Supabase credentials. Use the build script to include them:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _P.muted, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _P.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _P.border.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      './scripts/build.sh apk',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _P.primary,
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Make sure .env.local contains SUPABASE_URL and SUPABASE_ANON_KEY.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: _P.muted, fontSize: 12, height: 1.5),
                  ),
                  if (buildNumber.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'build $buildNumber',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _P.muted, fontSize: 11),
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
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const onboarding.OnboardingScreen(),
    ),
    GoRoute(path: '/circles', builder: (_, __) => const CirclesScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/reset-password',
      builder: (_, __) => const ResetPasswordScreen(),
    ),
    GoRoute(
      path: '/mfa-challenge',
      builder: (_, __) => const MfaChallengeScreen(),
    ),
    GoRoute(
      path: '/confirm',
      builder: (_, state) => ConfirmationScreen(
        email: state.extra is String ? state.extra as String : '',
      ),
    ),
    GoRoute(
      path: '/conversations',
      builder: (_, __) => const ConversationListScreen(),
    ),
    GoRoute(
      path: '/suggest-friends',
      builder: (_, __) => const SuggestFriendsScreen(),
    ),
    GoRoute(path: '/status', builder: (_, __) => const StatusScreen()),
    GoRoute(
      path: '/status/new',
      builder: (_, state) => StatusComposerScreen(
        initialSource: state.uri.queryParameters['source'],
      ),
    ),
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
      path: '/settings/notifications',
      builder: (_, __) => const NotificationSettingsScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const AccountSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/close-friends',
      builder: (_, __) => const CloseFriendsScreen(),
    ),
    GoRoute(
      path: '/settings/linked-devices',
      builder: (_, __) => const LinkedDevicesScreen(),
    ),
    GoRoute(
      path: '/settings/digital-avatar',
      builder: (_, __) => const DigitalAvatarScreen(),
    ),
    GoRoute(
      path: '/recent-calls',
      builder: (_, state) => RecentCallsScreen(
        key: ValueKey(state.uri),
        highlight: PushMessageTarget.isId(state.uri.queryParameters['id'])
            ? state.uri.queryParameters['id']
            : null,
      ),
    ),
    GoRoute(
      path: '/call/:conversationId',
      builder: (_, state) => CallScreen(
        conversationId: state.pathParameters['conversationId']!,
        peer: state.extra as Profile,
        callId: state.uri.queryParameters['id']!,
        video: state.uri.queryParameters['video'] == 'true',
        outgoing: state.uri.queryParameters['outgoing'] == 'true',
      ),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (_, state) => ChatScreen(
        conversationId: state.pathParameters['conversationId']!,
        initialPeer: state.extra is Profile ? state.extra as Profile : null,
      ),
    ),
    GoRoute(
      path: '/profile/:userId',
      builder: (_, state) =>
          UserProfileScreen(userId: state.pathParameters['userId']!),
    ),
    GoRoute(
      path: '/friendship-timeline/:userId',
      builder: (_, state) => FriendshipTimelineScreen(
        peerId: state.pathParameters['userId']!,
        peer: state.extra is Profile ? state.extra as Profile : null,
      ),
    ),
  ],
  redirect: (context, state) {
    final authed = Supa.currentUser != null;
    final location = state.matchedLocation;
    final isOnboarding = location == '/onboarding';
    final loggingIn = location == '/login';
    final resettingPassword = location == '/reset-password';
    final mfaChallenge = location == '/mfa-challenge';
    if (!authed) {
      if (!onboarding.onboardingCompleted) {
        return isOnboarding ? null : '/onboarding';
      }
      if (isOnboarding) return '/login';
      if (!loggingIn && !resettingPassword) return '/login';
      return null;
    }
    if (Supa.passwordRecoveryPending.value) {
      return resettingPassword ? null : '/reset-password';
    }
    if (Supa.needsMfaChallenge()) {
      return mfaChallenge ? null : '/mfa-challenge';
    }
    if (isOnboarding ||
        loggingIn ||
        mfaChallenge ||
        (location.startsWith('/call/') &&
            (state.extra is! Profile ||
                !PushMessageTarget.isId(state.uri.queryParameters['id'])))) {
      return '/conversations';
    }
    return null;
  },
);

class BroApp extends StatefulWidget {
  const BroApp({super.key});

  @override
  State<BroApp> createState() => _BroAppState();
}

class _BroAppState extends State<BroApp> with WidgetsBindingObserver {
  final CallFeedback _incomingFeedback = CallFeedback();
  bool _appLocked = false;
  DateTime? _pausedAt;
  StreamSubscription<AuthState>? _authSub;
  Timer? _incomingTimer;
  Timer? _ringTimer;
  DialogRoute<bool>? _incomingDialog;
  CallRecord? _promptedCall;
  bool _checkingIncoming = false;
  bool _foreground = true;
  String get _activeLocation {
    final matches = _router.routerDelegate.currentConfiguration;
    return matches.isEmpty ? '/' : matches.last.matchedLocation;
  }

  void _closeIncoming() {
    _ringTimer?.cancel();
    _ringTimer = null;
    unawaited(_incomingFeedback.stop());
    final route = _incomingDialog;
    if (route?.isActive == true) route!.navigator?.removeRoute(route);
  }

  Future<void> _pollIncoming() async {
    if (!mounted || !_foreground || _appLocked || _checkingIncoming) return;
    final owner = Supa.currentUser?.id;
    final navigator = _rootNav.currentState;
    final location = _activeLocation;
    if (owner == null ||
        navigator == null ||
        location.startsWith('/call/') ||
        !ConnectionMonitor.isOnline.value) {
      return;
    }
    _checkingIncoming = true;
    try {
      final current = _promptedCall;
      if (current != null) {
        if (!current.expiresAt.isAfter(DateTime.now())) {
          _closeIncoming();
        } else {
          final fresh = await Calls.get(current.id);
          if (_promptedCall?.id == current.id &&
              fresh?.status != CallStatus.ringing) {
            _closeIncoming();
          }
        }
        return;
      }
      final record = await Calls.incoming(owner);
      if (record == null) return;
      final peer = await Supa.getProfile(
        record.callerId,
      ).timeout(Calls.timeout);
      if (!mounted ||
          !navigator.mounted ||
          peer == null ||
          Supa.currentUser?.id != owner ||
          !_foreground ||
          _appLocked ||
          !record.expiresAt.isAfter(DateTime.now()) ||
          _activeLocation.startsWith('/call/')) {
        return;
      }
      final dialog = DialogRoute<bool>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFF202229),
            insetPadding: const EdgeInsets.symmetric(horizontal: 22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: Colors.white12),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5965E8).withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        record.video ? Icons.videocam_rounded : Icons.call,
                        color: const Color(0xFF9CA5FF),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      record.video
                          ? 'Incoming video call'
                          : 'Incoming voice call',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFF343640),
                      backgroundImage: peer.avatarUrl == null
                          ? null
                          : NetworkImage(peer.avatarUrl!),
                      child: peer.avatarUrl == null
                          ? Text(
                              peer.peerInitial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      peer.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${peer.username} is calling you',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context, false),
                              icon: const Icon(Icons.call_end_rounded),
                              label: const Text('Decline'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF7777),
                                side:
                                    const BorderSide(color: Color(0x66FF7777)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: () => Navigator.pop(context, true),
                              icon: const Icon(Icons.call_rounded),
                              label: const Text('Answer'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF36B875),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      _promptedCall = record;
      _incomingDialog = dialog;
      // Foreground incoming calls need an audible cue before the user answers.
      // Browsers may suppress it until the user has interacted with the page.
      unawaited(_incomingFeedback.play(CallFeedbackCue.ringtone));
      _ringTimer?.cancel();
      _ringTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (_incomingDialog == dialog && _foreground && !_appLocked) {
          unawaited(_incomingFeedback.play(CallFeedbackCue.ringtone));
        }
      });
      // Let the timer reconcile remote cancellation while the prompt is open.
      unawaited(
        navigator.push(dialog).then((answer) async {
          if (_incomingDialog != dialog) return;
          _incomingDialog = null;
          _ringTimer?.cancel();
          _ringTimer = null;
          unawaited(_incomingFeedback.stop());
          _promptedCall = null;
          if (!mounted ||
              Supa.currentUser?.id != owner ||
              !_foreground ||
              _appLocked ||
              answer == null ||
              !record.expiresAt.isAfter(DateTime.now())) {
            return;
          }
          if (answer) {
            if (!_activeLocation.startsWith(
              '/call/',
            )) {
              unawaited(
                _router.push(
                  Calls.route(
                    record.conversationId,
                    record.id,
                    record.video,
                    false,
                  ),
                  extra: peer,
                ),
              );
            }
          } else {
            try {
              await Calls.advance(record.id, 'reject');
            } catch (_) {}
          }
        }),
      );
    } catch (_) {
      // The next poll reconciles; the server expires calls independently.
    } finally {
      _checkingIncoming = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConnectionMonitor.start();
    Presence.bind();
    _incomingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollIncoming()),
    );
    _authSub = Supa.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        Supa.passwordRecoveryPending.value = true;
        Presence.resume();
        _router.go('/reset-password');
      } else if (state.session != null) {
        Presence.resume();
        unawaited(Supa.initializeEncryptionKeys().catchError((Object _) {}));
      } else {
        Supa.passwordRecoveryPending.value = false;
        Presence.unbind();
        LegacyMessaging.reset();
        _closeIncoming();
      }
    });
    PushNotifications.setOpenHandler((target) {
      if (!mounted) return;
      final uri = _router.routeInformationProvider.value.uri;
      if (_activeLocation.startsWith('/call/')) return;
      if (target.incoming) {
        unawaited(_pollIncoming());
      } else if (target.missed) {
        if (uri.path != '/recent-calls' ||
            uri.queryParameters['id'] != target.callId) {
          _router.go('/recent-calls?id=${target.callId}');
        }
      } else if (uri.path != '/chat/${target.conversationId}') {
        _router.go('/chat/${target.conversationId}');
      }
    });
    AppLock.enabled.addListener(_onLockPref);
    unawaited(AppLock.bootstrap());
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptUpdate());
    _startBackgroundUpdateChecks();
  }

  void _onLockPref() {
    if (!mounted) return;
    if (AppLock.enabled.value) {
      _closeIncoming();
      setState(() => _appLocked = true);
    } else {
      setState(() => _appLocked = false);
    }
  }

  Future<void> _maybePromptUpdate() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final ctx = _rootNav.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await AppUpdate.promptIfNeeded(context: ctx, currentVersion: appVersion);
  }

  /// Start periodic background update checks (every 6 hours).
  void _startBackgroundUpdateChecks() {
    unawaited(_periodicUpdateCheck());
  }

  Future<void> _periodicUpdateCheck() async {
    // Check immediately in the background, then every 6 hours
    while (mounted) {
      await Future<void>.delayed(AppUpdate.checkInterval);
      if (!mounted) break;
      try {
        final update = await AppUpdate.backgroundCheck(appVersion);
        if (update == null || !mounted || !_foreground) continue;
        final ctx = _rootNav.currentContext;
        if (ctx == null || !ctx.mounted) continue;
        await AppUpdate.promptIfNeeded(
          context: ctx,
          currentVersion: appVersion,
          latest: update,
        );
      } catch (_) {
        // Silently ignore background check failures
      }
    }
  }

  @override
  void dispose() {
    _incomingTimer?.cancel();
    _ringTimer?.cancel();
    unawaited(_incomingFeedback.dispose());
    _authSub?.cancel();
    Presence.unbind();
    AppLock.enabled.removeListener(_onLockPref);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ConnectionMonitor.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      Presence.resume();
      PushNotifications.refresh();
      unawaited(_lockIfTimedOut());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _closeIncoming();
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
      alignment: Alignment.topLeft,
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
            fontFamily: 'Space Grotesk',
            scaffoldBackgroundColor: _P.bg,
            colorScheme: ColorScheme.dark(
              primary: _P.primary,
              onPrimary: _P.darkOnAccent,
              surface: _P.surface,
              surfaceContainerHighest: _P.surfaceHigh,
              onSurface: _P.text,
              outline: _P.border,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: _P.bg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleTextStyle: TextStyle(
                color: _P.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            cardTheme: CardThemeData(
              color: _P.surface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _P.border.withValues(alpha: 0.35)),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: _P.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: _P.border.withValues(alpha: 0.4)),
              ),
              titleTextStyle: const TextStyle(
                color: _P.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: _P.surface,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: _P.surfaceHigh,
              contentTextStyle: const TextStyle(color: _P.text),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              behavior: SnackBarBehavior.floating,
            ),
            dividerTheme: DividerThemeData(
              color: _P.border.withValues(alpha: 0.4),
              space: 1,
              thickness: 1,
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: _P.primary,
              foregroundColor: _P.darkOnAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
            textTheme: const TextTheme(bodyMedium: TextStyle(color: _P.text)),
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
