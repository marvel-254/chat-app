import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/linked_device.dart';
import 'supabase.dart';

/// Device registry and session controls for the current Supabase account.
class LinkedDevices {
  LinkedDevices._();

  static const _deviceIdKey = 'linked_devices.device_id';
  static const _uuid = Uuid();

  static Future<String> currentDeviceId() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _uuid.v4();
    await preferences.setString(_deviceIdKey, generated);
    return generated;
  }

  static String currentDeviceName() {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android device',
      TargetPlatform.iOS => 'iPhone or iPad',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.linux => 'Linux computer',
      TargetPlatform.fuchsia => 'Fuchsia device',
    };
  }

  static String currentPlatform() {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
  }

  static Future<LinkedDevice> registerCurrentDevice() async {
    final user = Supa.currentUser;
    if (user == null) throw StateError('You need to be signed in.');

    final deviceId = await currentDeviceId();
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await Supa.client
        .from('linked_devices')
        .upsert(
          {
            'user_id': user.id,
            'device_id': deviceId,
            'device_name': currentDeviceName(),
            'platform': currentPlatform(),
            'last_seen_at': now,
            'revoked_at': null,
          },
          onConflict: 'user_id,device_id',
        )
        .select()
        .single();
    return LinkedDevice.fromJson(row, currentDeviceId: deviceId);
  }

  static Future<void> registerCurrentDeviceSilently() async {
    try {
      await registerCurrentDevice();
    } catch (_) {
      // A missing or not-yet-deployed registry must never block sign-in.
    }
  }

  static Future<List<LinkedDevice>> listDevices() async {
    final user = Supa.currentUser;
    if (user == null) return const [];
    final deviceId = await currentDeviceId();
    final rows = await Supa.client
        .from('linked_devices')
        .select()
        .eq('user_id', user.id)
        .filter('revoked_at', 'is', null)
        .order('last_seen_at', ascending: false);
    return (rows as List)
        .map((row) => LinkedDevice.fromJson(
              Map<String, dynamic>.from(row as Map),
              currentDeviceId: deviceId,
            ))
        .toList();
  }

  static Future<void> revokeDevice(LinkedDevice device) async {
    final user = Supa.currentUser;
    if (user == null) throw StateError('You need to be signed in.');
    final currentId = await currentDeviceId();
    if (device.deviceId == currentId) {
      throw StateError('This device cannot be removed while it is in use.');
    }
    await Supa.client
        .from('linked_devices')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', device.id)
        .eq('user_id', user.id);
  }

  /// Revokes all Supabase sessions except this one, then hides their registry
  /// entries. Supabase does not expose a client API for selecting one session
  /// by device ID, so this is intentionally an all-other-sessions operation.
  static Future<void> signOutOtherSessions() async {
    final user = Supa.currentUser;
    if (user == null) throw StateError('You need to be signed in.');
    final currentId = await currentDeviceId();

    await Supa.client.auth.signOut(scope: SignOutScope.others);
    await Supa.client
        .from('linked_devices')
        .update({'revoked_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', user.id)
        .neq('device_id', currentId)
        .filter('revoked_at', 'is', null);
  }
}
