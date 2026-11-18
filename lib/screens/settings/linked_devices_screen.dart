import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/linked_device.dart';
import '../../services/linked_devices.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../ui/errors.dart';
import '../../ui/states.dart';
import '../../widgets/responsive_app_shell.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<LinkedDevice> _devices = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      await LinkedDevices.registerCurrentDevice();
      final devices = await LinkedDevices.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(
          error,
          fallback: "We couldn't load your linked devices right now.",
        );
      });
    }
  }

  Future<void> _revoke(LinkedDevice device) async {
    final shouldRemove = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove this device?'),
            content: Text(
              '${device.deviceName} will be removed from your BRO device list. '
              'This does not sign that device out of Supabase; use “Sign out all '
              'other sessions” below for server-side session revocation.',
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => context.pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldRemove || !mounted) return;

    setState(() => _busy = true);
    try {
      await LinkedDevices.revokeDevice(device);
      if (!mounted) return;
      setState(() {
        _devices = _devices.where((entry) => entry.id != device.id).toList();
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device removed from your list.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  Future<void> _signOutOtherSessions() async {
    final shouldSignOut = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign out other sessions?'),
            content: const Text(
              'BRO will revoke every other Supabase session for this account. '
              'This device will stay signed in.',
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => context.pop(true),
                child: const Text('Sign out others'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldSignOut || !mounted) return;

    setState(() => _busy = true);
    try {
      await LinkedDevices.signOutOtherSessions();
      final devices = await LinkedDevices.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Other sessions signed out.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _devices.where((device) => device.isCurrent).firstOrNull;
    final others = _devices.where((device) => !device.isCurrent).toList();

    return ResponsiveAppShell(
      title: 'Linked devices',
      navIndex: 0,
      showBottomNavigation: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _loading
              ? const FormSkeleton(label: 'Loading linked devices')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text(
                        'See where your BRO account is registered. Last-seen times '
                        'come from the app that last connected.',
                        style: TextStyle(
                          color: app_colors.P.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_error != null) SoftErrorBanner(message: _error!),
                      if (_error != null) const SizedBox(height: 12),
                      Text(
                        'This device',
                        style: TextStyle(
                          color: app_colors.P.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (current != null)
                        _DeviceCard(device: current, current: true)
                      else
                        const _EmptyDeviceCard(
                          message: 'This device has not been registered yet.',
                        ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Other authorized devices',
                            style: TextStyle(
                              color: app_colors.P.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (others.isNotEmpty)
                            Text(
                              '${others.length}',
                              style: const TextStyle(color: app_colors.P.muted),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (others.isEmpty)
                        const _EmptyDeviceCard(
                          message: 'No other active devices are linked.',
                        )
                      else
                        ...others.map(
                          (device) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DeviceCard(
                              device: device,
                              onRevoke: _busy ? null : () => _revoke(device),
                            ),
                          ),
                        ),
                      if (others.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _signOutOtherSessions,
                          icon: const Icon(Icons.logout_outlined),
                          label: const Text('Sign out all other sessions'),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'This is the server-backed control. Removing one device '
                          'only removes its registry entry because Supabase does not '
                          'offer client-side revocation for one selected session.',
                          style: TextStyle(
                            color: app_colors.P.muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    this.current = false,
    this.onRevoke,
  });

  final LinkedDevice device;
  final bool current;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: app_colors.P.surfaceHigh,
          child: Icon(
            current ? Icons.phone_android_outlined : Icons.devices_outlined,
            color: app_colors.P.primary,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                device.deviceName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (current)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: app_colors.P.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'CURRENT',
                  style: TextStyle(
                    color: app_colors.P.darkOnAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${device.platform} · Last seen ${formatLinkedDeviceTimestamp(device.lastSeenAt)}',
          style: const TextStyle(color: app_colors.P.muted, fontSize: 12),
        ),
        trailing: current
            ? null
            : IconButton(
                tooltip: 'Remove device',
                onPressed: onRevoke,
                icon: const Icon(Icons.remove_circle_outline),
              ),
      ),
    );
  }
}

class _EmptyDeviceCard extends StatelessWidget {
  const _EmptyDeviceCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            message,
            style: const TextStyle(color: app_colors.P.muted),
          ),
        ),
      );
}
