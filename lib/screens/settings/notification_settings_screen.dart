import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/push_notifications.dart';
import '../../services/supabase.dart';
import '../../widgets/responsive_app_shell.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final String _owner;
  Map<String, dynamic>? _preferences;
  bool _busy = false;
  bool get _current => mounted && Supa.currentUser?.id == _owner;

  @override
  void initState() {
    super.initState();
    _owner = Supa.currentUser!.id;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final row = await Supa.client
          .from('bro_notification_preferences')
          .select()
          .eq('user_id', _owner)
          .maybeSingle();
      if (_current) setState(() => _preferences = row ?? {});
    } catch (_) {
      _notice('Could not load notification preferences.');
    }
  }

  void _notice(String text) {
    if (_current) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _update(String key, bool enabled) async {
    if (!_current || _busy) return;
    setState(() => _busy = true);
    try {
      await Supa.client.from('bro_notification_preferences').upsert({
        'user_id': _owner,
        key: enabled,
      });
      if (_current) setState(() => _preferences?[key] = enabled);
    } catch (_) {
      _notice('Could not save your preference.');
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    if (!_current) return;
    setState(() => _busy = true);
    final ready = await PushNotifications.retryInitialization();
    if (_current) setState(() => _busy = false);
    _notice(ready
        ? 'Push is ready. Tap enable to finish.'
        : PushNotifications.initializationError ??
            'Push is still unavailable on this device.');
  }

  Future<void> _enable() async {
    try {
      await PushNotifications.enable();
      _notice('Notifications enabled on this device.');
    } catch (_) {
      _notice(
        'Notifications are unavailable or blocked. Check your browser or device settings and connection.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ResponsiveAppShell(
        title: 'Notifications',
        navIndex: 0,
        showBottomNavigation: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Get alerts for new messages and calls even when BRO is not open. Alerts never include message text or the sender’s name.',
                ),
                const SizedBox(height: 12),
                if (PushNotifications.available)
                  FilledButton(
                    onPressed: _busy ? null : _enable,
                    child: const Text('Enable notifications on this device'),
                  )
                else
                  Text(PushNotifications.initializationError ??
                      'Push is not configured for this build or platform.'),
                if (PushNotifications.configured &&
                    !PushNotifications.available &&
                    PushNotifications.initializationError != null)
                  TextButton(
                    onPressed: _busy ? null : _retry,
                    child: const Text('Try again'),
                  ),
                const SizedBox(height: 12),
                if (_preferences == null)
                  TextButton(
                      onPressed: _load, child: const Text('Reload preferences')),
                for (final preference in {
                  'messages': 'Messages and reminders',
                  'calls': 'Incoming and missed calls',
                }.entries)
                  SwitchListTile(
                    title: Text(preference.value),
                    value: _preferences?[preference.key] as bool? ?? true,
                    onChanged: _busy || _preferences == null
                        ? null
                        : (enabled) => _update(preference.key, enabled),
                  ),
              ],
            ),
          ),
        ),
      );
}
