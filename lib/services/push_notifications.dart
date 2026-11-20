import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_message_target.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase.dart';

final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotifications {
  PushNotifications._();

  static StreamSubscription<AuthState>? _authSubscription;
  static StreamSubscription<String>? _registrationSubscription;
  static const _vapid = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
  static PushMessageTarget? _pendingTarget;
  static String? _suspendedUserId;
  static const _noticeBody = 'You have a new message.';
  static void Function(String conversationId)? _openHandler;
  static bool _initialized = false;

  static bool get _supportedPlatform =>
      kIsWeb ||
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (_initialized || !_supportedPlatform) return;
    _initialized = true;
    if (!kIsWeb)
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
    final messaging = FirebaseMessaging.instance;

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForegroundNotice(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
    _registrationSubscription = messaging.onTokenRefresh.listen((token) {
      final owner = _activeUserId;
      if (owner != null) unawaited(_sync(owner, prompt: false));
    });
    if (kIsWeb) {
      _pendingTarget = PushMessageTarget.fromData(Uri.base.queryParameters);
    }
    _authSubscription = Supa.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _pendingTarget = null;
        _suspendedUserId = null;
        appScaffoldMessengerKey.currentState?.clearSnackBars();
      } else if (state.session != null) {
        unawaited(_openPending());
        if (state.event == AuthChangeEvent.signedIn) {
          unawaited(_sync(state.session!.user.id, prompt: false));
        }
      }
    });
    try {
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) _openMessage(initialMessage);
    } catch (_) {
      debugPrint('Could not read the launch notification.');
    }
    if (_activeUserId != null) {
      unawaited(_openPending());
      await _sync(_activeUserId!, prompt: false);
    }
  }

  static String? get _activeUserId {
    final id = Supa.currentUser?.id;
    return id == _suspendedUserId ? null : id;
  }

  static Future<bool> enable() async {
    final owner = _activeUserId;
    if (!_initialized || owner == null) return false;
    return _sync(owner, prompt: true);
  }

  static Future<bool> _sync(String owner, {required bool prompt}) async {
    try {
      final messaging = FirebaseMessaging.instance;
      if (kIsWeb && _vapid.isEmpty) return false;
      final settings = prompt
          ? await messaging.requestPermission()
          : await messaging.getNotificationSettings();
      if (_activeUserId != owner) return false;
      final prefs = await SharedPreferences.getInstance();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        await Supa.removePushToken(owner);
        return false;
      }
      if (prompt) await prefs.setBool('push.enabled.$owner', true);
      if (kIsWeb && prefs.getBool('push.enabled.$owner') != true) return false;
      final token = await messaging.getToken(
          vapidKey: kIsWeb ? _vapid : null,
          serviceWorkerScriptPath: kIsWeb ? 'service-worker.js' : null);
      if (token == null || _activeUserId != owner) return false;
      await Supa.savePushToken(
          token, kIsWeb ? 'web' : defaultTargetPlatform.name, owner);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> unregisterCurrentToken() async {
    final owner = _activeUserId;
    if (!_supportedPlatform || owner == null) return;
    _suspendedUserId = owner;
    _pendingTarget = null;
    try {
      await Supa.removePushToken(owner).timeout(const Duration(seconds: 4));
    } catch (_) {}
    if (_initialized) {
      try {
        await FirebaseMessaging.instance
            .deleteToken()
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    await (await SharedPreferences.getInstance()).remove('push.enabled.$owner');
  }

  static Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _registrationSubscription?.cancel();
  }

  static void setOpenHandler(void Function(String) handler) {
    _openHandler = handler;
    unawaited(_openPending());
  }

  static void _openMessage(RemoteMessage message) {
    final target = PushMessageTarget.fromData(message.data);
    if (target == null) return;
    _pendingTarget = target;
    unawaited(_openPending());
  }

  static Future<void> _openPending() async {
    final target = _pendingTarget;
    final handler = _openHandler;
    if (target == null || handler == null) return;
    final userId = _activeUserId;
    if (userId == null) return;
    _pendingTarget = null;
    if (await _canShow(target, userId) && _activeUserId == userId) {
      handler(target.conversationId);
    }
  }

  static Future<bool> _canShow(PushMessageTarget target, String userId) async {
    final recipient = target.recipientUserId;
    if (recipient != null && recipient != userId) return false;
    try {
      final row = await Supa.client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', target.conversationId)
          .eq('user_id', userId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _showForegroundNotice(RemoteMessage message) async {
    final userId = _activeUserId;
    final target = PushMessageTarget.fromData(message.data);
    if (userId == null ||
        target == null ||
        !await _canShow(target, userId) ||
        _activeUserId != userId) return;

    final messenger = appScaffoldMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: const Text(_noticeBody),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'Open',
        onPressed: () {
          if (_activeUserId == userId) _openMessage(message);
        },
      ),
    ));
  }
}
