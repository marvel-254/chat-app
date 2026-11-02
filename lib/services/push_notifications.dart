import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static String? _fid;
  static String? _pendingConversationId;
  static void Function(String conversationId)? _openHandler;
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

    FirebaseMessaging.onMessage.listen(_showForegroundNotice);
    FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) _openMessage(initialMessage);

    _registrationSubscription = messaging.onRegistered.listen((fid) {
      _fid = fid;
      unawaited(_registerToken());
    });
    _authSubscription = Supa.authStateChanges.listen((state) {
      if (state.session != null) unawaited(_requestPermissionAndRegister());
    });
    if (Supa.currentUser != null) await _requestPermissionAndRegister();
  }

  static Future<void> _requestPermissionAndRegister() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      await messaging.register();
      await _registerToken();
    } catch (error) {
      debugPrint('Push notification registration failed: $error');
    }
  }

  static Future<void> _registerToken() async {
    final fid = _fid;
    if (fid == null || Supa.currentUser == null) return;
    try {
      await Supa.savePushToken(fid, defaultTargetPlatform.name);
    } catch (error) {
      debugPrint('Could not save push token: $error');
    }
  }

  static Future<void> unregisterCurrentToken() async {
    if (!_supportedPlatform) return;
    final fid = _fid;
    if (fid != null) await Supa.removePushToken(fid);
    await FirebaseMessaging.instance.unregister();
    _fid = null;
  }

  static Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _registrationSubscription?.cancel();
  }

  static void setOpenHandler(void Function(String) handler) {
    _openHandler = handler;
    final pending = _pendingConversationId;
    _pendingConversationId = null;
    if (pending != null) handler(pending);
  }

  static void _openMessage(RemoteMessage message) {
    final conversationId = message.data['conversation_id'] as String?;
    if (conversationId == null || conversationId.isEmpty) return;
    final handler = _openHandler;
    if (handler == null) {
      _pendingConversationId = conversationId;
    } else {
      handler(conversationId);
    }
  }

  static void _showForegroundNotice(RemoteMessage message) {
    final notice = message.notification;
    if (notice == null) return;
    appScaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text('${notice.title ?? 'New message'}: ${notice.body ?? ''}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
