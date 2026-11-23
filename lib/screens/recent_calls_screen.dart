import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../models/call_record.dart';
import '../models/profile.dart';
import '../services/calls.dart';
import '../services/connection_monitor.dart';
import '../ui/errors.dart';
import '../services/supabase.dart';
import '../widgets/responsive_app_shell.dart';

class RecentCallsScreen extends StatefulWidget {
  const RecentCallsScreen({super.key, this.highlight});
  final String? highlight;

  @override
  State<RecentCallsScreen> createState() => _RecentCallsScreenState();
}

class _RecentCallsScreenState extends State<RecentCallsScreen> {
  late final String _owner;
  final _peers = <String, Profile>{};
  List<CallRecord> _records = [];
  CallFilter _filter = CallFilter.all;
  bool _loading = true, _syncing = false, _unavailable = false, _opened = false;
  Timer? _refresh;
  StreamSubscription<AuthState>? _auth;
  bool get _current => mounted && Supa.currentUser?.id == _owner;

  @override
  void initState() {
    super.initState();
    _owner = Supa.currentUser!.id;
    _auth = Supa.authStateChanges.listen((_) {
      if (mounted && !_current) {
        setState(() {
          _records = [];
          _peers.clear();
        });
      }
    });
    unawaited(_initialize());
    ConnectionMonitor.isOnline.addListener(_networkChanged);
    _refresh = Timer.periodic(const Duration(seconds: 12), (_) {
      if (_current && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  Future<void> _initialize() async {
    final cached = await Calls.cached(_owner);
    if (!_current) return;
    // If cached data is available, show it immediately. If the cache was
    // skipped (expired TTL), the list is empty and we show loading state.
    if (cached.isNotEmpty) {
      setState(() => _records = cached);
    }
    await _load();
  }

  void _networkChanged() {
    if (_current) setState(() {});
    if (ConnectionMonitor.isOnline.value) unawaited(_load());
  }

  Future<void> _load() async {
    if (!_current || _syncing) return;
    debugPrint('Loading call history for $_owner');
    _syncing = true;
    try {
      final records = await Calls.recent(_owner);
      debugPrint('Fetched ${records.length} call records');
      final cachedNames = {
        for (final record in _records)
          record.peerId(_owner): record.cachedContact
      };
      var profilesFresh = false;
      if (!_current) return;
      setState(() {
        _records = records
            .map((record) =>
                record.withCachedContact(cachedNames[record.peerId(_owner)]))
            .toList();
        _unavailable = false;
      });
      final ids = records.map((r) => r.peerId(_owner)).toSet();
      final highlight = widget.highlight;
      CallRecord? target;
      if (!_opened && highlight != null) {
        target = await Calls.get(highlight);
        if (target != null) ids.add(target.peerId(_owner));
      }
      if (!_current) return;
      if (ids.isNotEmpty) {
        try {
          final profiles = await Supa.client
              .from('visible_profiles')
              .select('id,name,avatar_url')
              .inFilter('id', ids.toList())
              .timeout(Calls.timeout);
          profilesFresh = true;
          if (_current) {
            setState(() {
              _peers.clear();
              for (final row in profiles) {
                final profile = Profile.fromJson(row);
                _peers[profile.id] = profile;
              }
            });
          }
        } catch (e) {
          debugPrint('Profile lookup failed: $e');
          // History remains useful if profile lookup is unavailable.
        }
      }
      if (!_current) return;
      final enriched = records.map((record) {
        final peerId = record.peerId(_owner);
        return record.withCachedContact(_peers[peerId]?.label ??
            (profilesFresh ? null : cachedNames[peerId]));
      }).toList();
      setState(() => _records = enriched);
      await Calls.cache(_owner, enriched);
      if (_current && !_opened && highlight != null) {
        _opened = true;
        if (target != null && target.status.terminal) {
          unawaited(_details(target));
        }
      }
    } catch (e) {
      debugPrint('Failed to load call history: $e');
      await Sentry.captureException(e);
      if (_current) setState(() => _unavailable = true);
    } finally {
      _syncing = false;
      if (_current && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _remove(String? id) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
              title: Text(
                  id == null ? 'Clear recent calls?' : 'Remove this call?'),
              content: const Text(
                  'This removes the entry from your BRO account, not from the other person’s history.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Keep')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Remove'))
              ],
            ));
    if (confirmed != true || !_current || _syncing) return;
    _syncing = true;
    try {
      await Calls.hide(_owner, id);
      if (_current) {
        setState(() => _records =
            _records.where((record) => id != null && record.id != id).toList());
      }
    } catch (e) {
      debugPrint('Failed to remove call history: $e');
      await Sentry.captureException(e);
      if (!mounted) return;
      if (_current) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not remove history. $kRetryDetail')));
      }
    } finally {
      _syncing = false;
    }
  }

  String _when(DateTime time) {
    final local = time.toLocal();
    final format = MaterialLocalizations.of(context);
    return '${format.formatMediumDate(local)} · ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Future<void> _details(CallRecord record) async {
    final peer = _peers[record.peerId(_owner)];
    final label = peer?.label ?? record.cachedContact ?? 'Contact';
    final direction = record.outgoing(_owner) ? 'Outgoing' : 'Incoming';
    final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label,
                              style: Theme.of(sheet).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(
                              '$direction ${record.video ? 'video' : 'voice'} · ${record.outcome(_owner)}'),
                          Text('Started: ${_when(record.startedAt)}'),
                          if (record.endedAt case final end?)
                            Text('Ended: ${_when(end)}'),
                          if (record.duration case final duration?)
                            Text(
                                'Duration: ${CallRecord.formatDuration(duration)}'),
                          if (record.status == CallStatus.failed)
                            Text(record.connectedAt == null
                                ? 'The call could not connect.'
                                : 'The connection was interrupted.'),
                          const SizedBox(height: 16),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if (peer != null &&
                                ConnectionMonitor.isOnline.value) ...[
                              FilledButton.icon(
                                  onPressed: () =>
                                      Navigator.pop(sheet, 'voice'),
                                  icon: const Icon(Icons.call),
                                  label: const Text('Call back')),
                              OutlinedButton.icon(
                                  onPressed: () =>
                                      Navigator.pop(sheet, 'video'),
                                  icon: const Icon(Icons.videocam_outlined),
                                  label: const Text('Video call')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(sheet, 'profile'),
                                  child: const Text('View profile')),
                            ],
                            TextButton(
                                onPressed: ConnectionMonitor.isOnline.value
                                    ? () => Navigator.pop(sheet, 'remove')
                                    : null,
                                child: const Text('Remove entry')),
                          ]),
                        ],
                      ))),
            ));
    if (!_current) return;
    if (choice == 'remove') return _remove(record.id);
    if (peer == null) return;
    if (!mounted) return;
    if (choice == 'profile') {
      unawaited(context.push('/profile/${peer.id}'));
    } else if (choice == 'voice' || choice == 'video') {
      unawaited(context.push(
          Calls.route(
              record.conversationId, Calls.newId(), choice == 'video', true),
          extra: peer));
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    unawaited(_auth?.cancel());
    ConnectionMonitor.isOnline.removeListener(_networkChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _records.where((r) => r.matches(_filter, _owner)).toList();
    final online = ConnectionMonitor.isOnline.value;
    return ResponsiveAppShell(
      title: 'Recent Calls',
      navIndex: 3,
      actions: [
        IconButton(
            tooltip: 'Clear call history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed:
                online && _records.isNotEmpty ? () => _remove(null) : null)
      ],
      body: Column(children: [
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              for (final filter in CallFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                      label: Text(switch (filter) {
                        CallFilter.all => 'All',
                        CallFilter.missed => 'Missed',
                        CallFilter.incoming => 'Incoming',
                        CallFilter.outgoing => 'Outgoing',
                      }),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter)),
                )
            ])),
        if (!online || _unavailable)
          ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title:
                Text(online ? 'Couldn’t sync recent calls' : 'You’re offline'),
            subtitle:
                const Text('Only history saved on this device is available.'),
            trailing: TextButton(
                onPressed: online ? _load : null,
                child: const Text('Try again')),
          ),
        Expanded(
            child: _loading && visible.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.phone_in_talk_outlined, size: 40),
                        const SizedBox(height: 12),
                        Text(_filter == CallFilter.all
                            ? 'No recent calls'
                            : 'No calls match this filter'),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final r = visible[index];
                            final peer = _peers[r.peerId(_owner)];
                            final avatarUrl = peer?.avatarUrl;
                            final missed = r.matches(CallFilter.missed, _owner);
                            final issue =
                                missed || r.status == CallStatus.failed;
                            final duration = r.duration;
                            return ListTile(
                              key: ValueKey(r.id),
                              leading: CircleAvatar(
                                  foregroundImage: avatarUrl == null
                                      ? null
                                      : NetworkImage(avatarUrl),
                                  child: Text(peer?.peerInitial ??
                                      r.cachedContact
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      '?')),
                              title: Text(
                                  peer?.label ?? r.cachedContact ?? 'Contact'),
                              subtitle: Text(
                                  '${r.outgoing(_owner) ? 'Outgoing' : 'Incoming'} ${r.video ? 'video' : 'voice'} · ${r.outcome(_owner)}\n'
                                  '${_when(r.startedAt)}${duration == null ? '' : ' · ${CallRecord.formatDuration(duration)}'}'),
                              isThreeLine: true,
                              trailing: Icon(
                                  missed
                                      ? Icons.call_missed
                                      : r.status == CallStatus.failed
                                          ? Icons.error_outline
                                          : r.status == CallStatus.rejected
                                              ? Icons.call_end
                                              : r.video
                                                  ? Icons.videocam_outlined
                                                  : Icons.call_outlined,
                                  color: issue
                                      ? Theme.of(context).colorScheme.error
                                      : null),
                              onTap: () => _details(r),
                            );
                          },
                        ))),
      ]),
    );
  }
}
