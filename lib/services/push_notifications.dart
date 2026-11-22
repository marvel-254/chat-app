import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/call_record.dart';
import 'calls.dart';
import 'push_message_target.dart';
import 'supabase.dart';

final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushNotifications {
  PushNotifications._();

  static const webApiKey = String.fromEnvironment('FIREBASE_WEB_API_KEY');
  static const webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const webSender = String.fromEnvironment('FIREBASE_WEB_SENDER_ID');
  static const webProject = String.fromEnvironment('FIREBASE_WEB_PROJECT_ID');
  static const webVapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
  static const _storage = FlutterSecureStorage();
  static const _deviceKey = 'bro_push_device_v1';
  static const _ownerKey = 'bro_push_owner_v1';
  static const _timeout = Duration(seconds: 8);
  static final _shown = <String>{}, _opened = <String>{};
  static PushMessageTarget? _pending;
  static String? _suspendedUserId;
  static String? _lastOwner;
  static String? _deviceId;
  static void Function(PushMessageTarget)? _openHandler;
  static bool _initialized = false;
  static Future<void> _work = Future.value();
  static DateTime? _lastRefresh;
  static StreamSubscription<AuthState>? _authSub;

  static bool get configured => kIsWeb
      ? [
          webApiKey,
          webAppId,
          webSender,
          webProject,
          webVapidKey,
        ].every((value) => value.isNotEmpty)
      : defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> initialize({Uri? launchUri}) async {
    _authSub?.cancel();
    if (_initialized || !configured) return;
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: webApiKey,
          appId: webAppId,
          messagingSenderId: webSender,
          projectId: webProject,
        ),
      );
    } else {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
    }
    final messaging = FirebaseMessaging.instance;
    if (!await messaging.isSupported()) return;
    _deviceId = await _storage.read(key: _deviceKey) ?? const Uuid().v4();
    await _storage.write(key: _deviceKey, value: _deviceId);
    _lastOwner = await _storage.read(key: _ownerKey);
    _initialized = true;
    FirebaseMessaging.onMessage.listen(
      (message) => unawaited(_foreground(message)),
    );
    if (!kIsWeb) {
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _receive(message.data),
      );
      // Deliberately use the token API, not FID registration, with message.token.
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((_) => refresh(force: true));
    }
    // Store subscription to prevent memory leaks
    _authSub = Supa.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        _pending = null;
        _suspendedUserId = null;
        _shown.clear();
        _opened.clear();
        appScaffoldMessengerKey.currentState?.clearSnackBars();
      } else if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession) {
        unawaited(flushPending());
        refresh(force: true);
      }
    });
    if (kIsWeb) {
      final query = (launchUri ?? Uri.base).queryParameters;
      if (query['bro_push'] == '1') _receive(query);
    } else {
      final initial = await messaging.getInitialMessage();
      if (initial != null) _receive(initial.data);
    }
    refresh(force: true);
  }

  static String? get _activeUserId {
    final id = Supa.currentUser?.id;
    return id == _suspendedUserId ? null : id;
  }

  static Future<void> _serialize(Future<void> Function() action) {
    final next = _work.then((_) => action());
    _work = next.catchError((Object _) {});
    return next;
  }

  /// Permission must be requested directly from a user gesture on browsers.
  static Future<void> enable() async {
    final owner = _activeUserId;
    if (!_initialized || owner == null) {
      throw StateError('Notifications unavailable');
    }
    final permission = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (!_permitted(permission)) throw StateError('Notifications are blocked');
    await _serialize(() => _sync(owner));
  }

  static bool _permitted(NotificationSettings settings) =>
      settings.authorizationStatus == AuthorizationStatus.authorized ||
      settings.authorizationStatus == AuthorizationStatus.provisional;

  static void refresh({bool force = false}) {
    final owner = _activeUserId;
    if (!_initialized || owner == null) return;
    if (!force &&
        _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < const Duration(minutes: 2)) {
      return;
    }
    _lastRefresh = DateTime.now();
    unawaited(
      _serialize(() => _sync(owner)).catchError((Object _) {
        debugPrint('Notification registration unavailable.');
      }),
    );
  }

  static Future<void> _sync(String owner) async {
    if (_activeUserId != owner) return;
    final messaging = FirebaseMessaging.instance;
    if (!_permitted(
      await messaging.getNotificationSettings().timeout(_timeout),
    )) {
      await _deleteRegistration(owner);
      return;
    }
    if (_lastOwner != null && _lastOwner != owner) {
      // A new account must not inherit an existing account's push token.
      // ignore: deprecated_member_use
      await messaging.deleteToken().timeout(_timeout);
    }
    if (_activeUserId != owner) return;
    final worker =
        kIsWeb ? Uri.base.resolve('service-worker.js').toString() : null;
    final token = await messaging
        // ignore: deprecated_member_use
        .getToken(
          vapidKey: kIsWeb ? webVapidKey : null,
          serviceWorkerScriptPath: worker,
        )
        .timeout(_timeout);
    if (_activeUserId != owner) return;
    if (token == null || token.isEmpty) throw StateError('No push token');
    // Persist before the RPC: a process kill after registration still rotates on account switch.
    await _storage.write(key: _ownerKey, value: owner);
    _lastOwner = owner;
    if (_activeUserId != owner) return;
    await Supa.client.rpc(
      'register_bro_push',
      params: {
        'p_owner': owner,
        'p_device': _deviceId,
        'p_token': token,
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      },
    ).timeout(_timeout);
  }

  static Future<void> _deleteRegistration(String owner) async {
    if (Supa.currentUser?.id != owner || _deviceId == null) return;
    await Supa.client
        .from('bro_push_devices')
        .delete()
        .eq('user_id', owner)
        .eq('device_id', _deviceId!)
        .timeout(_timeout);
  }

  static Future<void> unregisterCurrentToken() async {
    final owner = Supa.currentUser?.id;
    if (owner == null || !_initialized) return;
    _authSub?.cancel();
    _suspendedUserId = owner;
    _pending = null;
    await _serialize(() async {
      await Future.wait([
        _deleteRegistration(owner).catchError((Object _) {}),
        FirebaseMessaging.instance
            // ignore: deprecated_member_use
            .deleteToken()
            .timeout(_timeout)
            .catchError((Object _) {}),
      ]);
    });
  }

  static void setOpenHandler(void Function(PushMessageTarget) handler) {
    _openHandler = handler;
    unawaited(flushPending());
  }

  static void _receive(Map<String, dynamic> data) {
    final target = PushMessageTarget.fromData(data);
    if (target == null) return;
    _pending = target;
    unawaited(flushPending());
  }

  static Future<void> flushPending() async {
    final target = _pending;
    final handler = _openHandler;
    final owner = _activeUserId;
    if (target == null || handler == null || owner == null) return;
    _pending = null;
    if (await _canShow(target, owner) &&
        _activeUserId == owner &&
        _once(_opened, target.eventId)) {
      handler(target);
    }
  }

  static bool _once(Set<String> seen, String? id) {
    if (id == null) return true;
    if (!seen.add(id)) return false;
    if (seen.length > 128) seen.remove(seen.first);
    return true;
  }

  static Future<bool> _canShow(PushMessageTarget target, String owner) async {
    if (target.recipientUserId != null && target.recipientUserId != owner) {
      return false;
    }
    try {
      final member = await Supa.client
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', target.conversationId)
          .eq('user_id', owner)
          .maybeSingle()
          .timeout(_timeout);
      if (member == null) return false;
      if (target.callId case final callId?) {
        final call = await Calls.get(callId);
        return call?.calleeId == owner &&
            call?.conversationId == target.conversationId &&
            (target.missed
                ? call?.status == CallStatus.missed
                : call?.status == CallStatus.ringing &&
                    call!.expiresAt.isAfter(DateTime.now()));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _foreground(RemoteMessage message) async {
    final owner = _activeUserId;
    final target = PushMessageTarget.fromData(message.data);
    if (owner == null ||
        target == null ||
        !await _canShow(target, owner) ||
        _activeUserId != owner ||
        !_once(_shown, target.eventId)) {
      return;
    }
    // Foreground ringing is presented by the call coordinator, not a second notice.
    if (target.incoming) return;
    final messenger = appScaffoldMessengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(target.notice),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            if (_activeUserId == owner) _receive(message.data);
          },
        ),
      ),
    );
  }
}
