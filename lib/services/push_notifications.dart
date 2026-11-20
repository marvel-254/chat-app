import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_message_target.dart';
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
  static String? _fcmToken;
  static PushMessageTarget? _pendingTarget;
  static String? _suspendedUserId;
  static const _noticeBody = 'You have a new message.';
  static void Function(String conversationId, String? callId)? _openHandler;
  static bool _initialized = false;

  static bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (_initialized || !_supportedPlatform) return;
    _initialized = true;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
    final messaging = FirebaseMessaging.instance;

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForegroundNotice(message));
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
    _registrationSubscription = messaging.onTokenRefresh.listen((token) {
      if (_activeUserId == null) return;
      _fcmToken = token;
      unawaited(_registerToken());
    });
    _authSubscription = Supa.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _pendingTarget = null;
        _suspendedUserId = null;
        appScaffoldMessengerKey.currentState?.clearSnackBars();
      } else if (state.session != null) {
        unawaited(_openPending());
        if (state.event == AuthChangeEvent.signedIn) {
          unawaited(_requestPermissionAndRegister());
        }
      }
    });
    try {
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) _openMessage(initialMessage);
    } catch (_) {
      debugPrint('Could not read the launch notification.');
    }
    if (_activeUserId != null) await _requestPermissionAndRegister();
  }

  static String? get _activeUserId {
    final id = Supa.currentUser?.id;
    return id == _suspendedUserId ? null : id;
  }

  static Future<void> _requestPermissionAndRegister() async {
    final owner = _activeUserId;
    if (owner == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (_activeUserId != owner ||
          settings.authorizationStatus == AuthorizationStatus.denied) return;
      if (_activeUserId == owner) await _registerToken();
    } catch (_) {
      debugPrint('Push notification registration failed.');
    }
  }

  static Future<void> _registerToken() async {
    if (_activeUserId == null) return;
    try {
      final token = _fcmToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _fcmToken = token;
      await Supa.savePushToken(token, defaultTargetPlatform.name);
    } catch (_) {
      debugPrint('Could not save the notification registration.');
    }
  }

  static Future<void> unregisterCurrentToken() async {
    if (!_supportedPlatform) return;
    _suspendedUserId = Supa.currentUser?.id;
    _pendingTarget = null;
    final token = _fcmToken ?? await FirebaseMessaging.instance.getToken();
    _fcmToken = null;
    try {
      if (token != null && token.isNotEmpty) {
        await Supa.removePushToken(token).timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      debugPrint('Could not remove the saved notification registration.');
    }
    try {
      await FirebaseMessaging.instance
          .deleteToken()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint('Could not delete this device notification token.');
    }
  }

  static Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _registrationSubscription?.cancel();
  }

  static void setOpenHandler(
      void Function(String conversationId, String? callId) handler) {
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
      handler(target.conversationId, target.callId);
    }
  }

  static Future<bool> _canShow(PushMessageTarget target, String userId) async {
    final recipient = target.recipientUserId;
    if (recipient != null) return recipient == userId;
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
