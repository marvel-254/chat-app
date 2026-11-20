import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../models/call_history.dart' as history;
import '../../models/profile.dart';
import '../../services/call_history.dart';
import '../../services/supabase.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../widgets/responsive_app_shell.dart';

/// Recent Calls screen. The data source and peer resolver are injectable so
/// the UI can be widget-tested without Supabase or platform channels.
class RecentCallsScreen extends StatefulWidget {
  const RecentCallsScreen({
    super.key,
    this.source,
    this.peerResolver,
    this.callIdToOpen,
  });

  final CallHistorySource? source;
  final Future<Profile?> Function(String peerId)? peerResolver;
  final String? callIdToOpen;

  @override
  State<RecentCallsScreen> createState() => _RecentCallsScreenState();
}

class _RecentCallsScreenState extends State<RecentCallsScreen> {
  late final CallHistorySource _source;
  String _filter = 'All';
  int _retryToken = 0;
  final _peers = <String, Profile?>{};
  final _loadingPeers = <String>{};

  static const _filters = <String>['All', 'Missed', 'Incoming', 'Outgoing'];

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? CallHistory();
    if (widget.callIdToOpen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openById(widget.callIdToOpen!));
      });
    }
  }

  Future<Profile?> _peer(String id) async {
    if (_peers.containsKey(id)) return _peers[id];
    return _loadPeer(id);
  }

  Future<Profile?> _loadPeer(String id) async {
    final resolver = widget.peerResolver ?? Supa.getProfile;
    try {
      final profile = await resolver(id);
      if (mounted) setState(() => _peers[id] = profile);
      return profile;
    } catch (_) {
      if (mounted) setState(() => _peers[id] = null);
      return null;
    } finally {
      _loadingPeers.remove(id);
    }
  }

  void _ensurePeers(List<history.CallRecord> records) {
    for (final record in records) {
      final id = record.peerUserId;
      if (_peers.containsKey(id) || _loadingPeers.contains(id)) continue;
      _loadingPeers.add(id);
      unawaited(_loadPeer(id));
    }
  }

  Future<void> _openById(String callId) async {
    final record = await _source.find(callId);
    if (record != null && mounted) _showDetails(record);
  }

  List<history.CallRecord> _applyFilter(List<history.CallRecord> records) {
    switch (_filter) {
      case 'Missed':
        return records
            .where((r) => r.isMissed || r.isFailed || r.isRejected)
            .toList();
      case 'Incoming':
        return records.where((r) => r.isIncoming).toList();
      case 'Outgoing':
        return records.where((r) => r.isOutgoing).toList();
      default:
        return records;
    }
  }

  static String _statusLabel(history.CallRecord record) {
    if (record.isMissed) return 'Missed';
    if (record.isFailed) return 'Failed';
    if (record.isRejected) return 'Rejected';
    if (record.isCancelled) return 'Cancelled';
    if (record.status == history.CallRecord.statusUnanswered) {
      return 'Unanswered';
    }
    return 'Completed';
  }

  static IconData _statusIcon(history.CallRecord record) {
    if (record.isMissed || record.isFailed) return Icons.call_missed_outgoing;
    if (record.isIncoming) return Icons.call_received;
    return Icons.call_made;
  }

  @override
  Widget build(BuildContext context) => ResponsiveAppShell(
        title: 'Recent Calls',
        subtitle: 'Calls across your devices',
        navIndex: 1,
        body: Column(
          children: [
            _buildFilters(),
            Expanded(
              child: StreamBuilder<CallHistorySnapshot>(
                key: ValueKey(_retryToken),
                stream: _source.watch(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const _CallHistorySkeleton();
                  }
                  final state = snapshot.data ??
                      const CallHistorySnapshot(<history.CallRecord>[],
                          isOffline: true);
                  _ensurePeers(state.records);
                  final records = _applyFilter(state.records);
                  return Column(
                    children: [
                      if (state.isOffline)
                        _OfflineBanner(
                          message: state.error ??
                              'You are offline. Showing saved calls.',
                          onRetry: () =>
                              setState(() => _retryToken++),
                        ),
                      Expanded(
                        child: records.isEmpty
                            ? _EmptyState(filter: _filter)
                            : RefreshIndicator(
                                onRefresh: _source.flushPending,
                                child: ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 8, 16, 24),
                                  itemCount: records.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) => _CallTile(
                                    key: ValueKey(
                                        'call-${records[index].callId}'),
                                    record: records[index],
                                    peer: _peers[records[index].peerUserId],
                                    statusLabel:
                                        _statusLabel(records[index]),
                                    statusIcon: _statusIcon(records[index]),
                                    onTap: () =>
                                        _showDetails(records[index]),
                                    onDelete: () =>
                                        _confirmDelete(records[index]),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear call history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmClearAll,
          ),
        ],
      );

  Widget _buildFilters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in _filters) ...[
                ChoiceChip(
                  label: Text(filter),
                  selected: _filter == filter,
                  selectedColor: app_colors.P.primary.withValues(alpha: 0.18),
                  backgroundColor: app_colors.P.surfaceHigh,
                  side: BorderSide(
                    color: _filter == filter
                        ? app_colors.P.primary.withValues(alpha: 0.5)
                        : app_colors.P.border.withValues(alpha: 0.35),
                  ),
                  labelStyle: TextStyle(
                    color: _filter == filter
                        ? app_colors.P.primary
                        : app_colors.P.muted,
                    fontWeight:
                        _filter == filter ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onSelected: (_) => setState(() => _filter = filter),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      );

  Future<void> _showDetails(history.CallRecord record) async {
    final peer = await _peer(record.peerUserId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: app_colors.P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CallDetailsSheet(
        record: record,
        peer: peer,
        statusLabel: _statusLabel(record),
        onVoice: () =>
            _startCall(sheetContext, record, video: false),
        onVideo: () => _startCall(sheetContext, record, video: true),
        onProfile: () {
          Navigator.pop(sheetContext);
          context.push('/profile/${record.peerUserId}');
        },
      ),
    );
  }

  Future<void> _startCall(
      BuildContext sheetContext, history.CallRecord record,
      {required bool video}) async {
    final profile = await _peer(record.peerUserId);
    if (!mounted || !sheetContext.mounted) return;
    Navigator.pop(sheetContext);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact details are unavailable.')),
      );
      return;
    }
    final callId = const Uuid().v4();
    context.push(
      '/call/${record.conversationId}?id=$callId&video=$video&outgoing=true',
      extra: profile,
    );
  }

  Future<void> _confirmDelete(history.CallRecord record) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: app_colors.P.surface,
        title: const Text('Delete call?'),
        content: const Text('This removes the entry from your call history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (accepted == true) await _source.delete(record.id);
  }

  Future<void> _confirmClearAll() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: app_colors.P.surface,
        title: const Text('Clear call history?'),
        content: const Text('This removes all calls from your history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (accepted == true) await _source.clear();
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    super.key,
    required this.record,
    required this.peer,
    required this.statusLabel,
    required this.statusIcon,
    required this.onTap,
    required this.onDelete,
  });

  final history.CallRecord record;
  final Profile? peer;
  final String statusLabel;
  final IconData statusIcon;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final highlight = record.isMissed || record.isFailed;
    return Material(
      color: app_colors.P.surface,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: CircleAvatar(
          backgroundColor: app_colors.P.surfaceHigh,
          backgroundImage:
              peer?.avatarUrl == null ? null : NetworkImage(peer!.avatarUrl!),
          child: peer?.avatarUrl != null
              ? null
              : Text(
                  (peer?.label ?? '?').substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: app_colors.P.text),
                ),
        ),
        title: Text(
          peer?.label ?? 'Unknown contact',
          style: TextStyle(
            color: highlight ? app_colors.P.primary : app_colors.P.text,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(statusIcon,
                size: 14,
                color: highlight ? app_colors.P.primary : app_colors.P.muted),
            const SizedBox(width: 5),
            Text(
              '$statusLabel · ${record.isVideo ? 'Video' : 'Voice'} · '
              '${_timeLabel(record.startedAt)}',
              style: const TextStyle(
                  color: app_colors.P.muted, fontSize: 12),
            ),
            if (record.hasDuration) ...[
              const SizedBox(width: 6),
              Text(
                history.formatCallDuration(record.durationSeconds),
                style: const TextStyle(
                    color: app_colors.P.muted, fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          tooltip: 'Delete call',
          icon: const Icon(Icons.more_vert, color: app_colors.P.muted),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }

  static String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return sameDay ? 'Today $time' : '${local.day}/${local.month} $time';
  }
}

class _CallDetailsSheet extends StatelessWidget {
  const _CallDetailsSheet({
    required this.record,
    required this.peer,
    required this.statusLabel,
    required this.onVoice,
    required this.onVideo,
    required this.onProfile,
  });

  final history.CallRecord record;
  final Profile? peer;
  final String statusLabel;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Call details',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: app_colors.P.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _row('Contact', peer?.label ?? 'Unknown contact'),
              _row('Type', record.isVideo ? 'Video' : 'Voice'),
              _row(
                  'Direction',
                  record.isIncoming ? 'Incoming' : 'Outgoing'),
              _row('Status', statusLabel),
              _row('Date', record.startedAt.toLocal().toString()),
              if (record.endedAt != null)
                _row('Ended', record.endedAt!.toLocal().toString()),
              _row(
                'Duration',
                record.hasDuration
                    ? history.formatCallDuration(record.durationSeconds)
                    : 'Not connected',
              ),
              if (record.failureReason != null)
                _row('Note', record.failureReason!),
              const SizedBox(height: 20),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onVoice,
                    icon: const Icon(Icons.call),
                    label: const Text('Call back'),
                  ),
                  const SizedBox(width: 10),
                  if (record.isVideo)
                    OutlinedButton.icon(
                      onPressed: onVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Video'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: onProfile,
                    child: const Text('View profile'),
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: const TextStyle(
                      color: app_colors.P.muted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: app_colors.P.text, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: app_colors.P.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: app_colors.P.muted, fontSize: 12))),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_end_outlined,
                  size: 48,
                  color: app_colors.P.muted.withValues(alpha: 0.6)),
              const SizedBox(height: 12),
              Text(
                filter == 'All' ? 'No calls yet' : 'No $filter calls',
                style: const TextStyle(
                    color: app_colors.P.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Calls you make or receive will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: app_colors.P.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
}

class _CallHistorySkeleton extends StatelessWidget {
  const _CallHistorySkeleton();

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => Container(
          height: 68,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: app_colors.P.surface,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
}
