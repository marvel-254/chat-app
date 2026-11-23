import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../models/circle.dart';
import '../models/profile.dart';
import '../services/circles.dart';
import '../services/supabase.dart';
import '../theme/app_colors.dart' as app_colors;
import '../ui/errors.dart';
import '../ui/states.dart';
import '../widgets/responsive_app_shell.dart';

class CircleDetailScreen extends StatefulWidget {
  final String circleId;

  const CircleDetailScreen({super.key, required this.circleId});

  @override
  State<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends State<CircleDetailScreen> {
  Circle? _circle;
  List<CircleMember> _members = [];
  List<Map<String, dynamic>> _invites = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        Circles.getCircle(widget.circleId),
        Circles.getCircleMembers(widget.circleId),
        Circles.isAdmin(widget.circleId),
        Circles.invitesForCircle(widget.circleId),
      ]);
      if (!mounted) return;
      setState(() {
        _circle = results[0] as Circle?;
        _members = (results[1] as List).cast<CircleMember>();
        _isAdmin = results[2] as bool;
        _invites = (results[3] as List).cast<Map<String, dynamic>>();
        _isLoading = false;
        _error = null;
      });
    } catch (e, st) {
      debugPrint('Failed to load circle: $e');
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _inviteMember() async {
    final profile = await showDialog<Profile>(
      context: context,
      builder: (_) => const _UserPickerDialog(),
    );
    if (profile == null || !mounted) return;
    try {
      await Circles.invite(widget.circleId, profile.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to ${profile.label}')),
      );
      await _load();
    } catch (e, st) {
      debugPrint('Circle invite failed: $e');
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not invite: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  Future<void> _respondToInvite(String inviteId, bool accept) async {
    try {
      if (accept) {
        await Circles.acceptInvite(inviteId);
      } else {
        await Circles.declineInvite(inviteId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accept ? 'Joined circle' : 'Invitation declined')),
      );
      await _load();
    } catch (e, st) {
      debugPrint('Circle invite response failed: $e');
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not respond: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  Future<void> _leaveCircle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Leave circle'),
        content: Text('Leave ${_circle?.name ?? 'this circle'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (confirmed != true || _circle == null) return;
    try {
      await Circles.leave(_circle!.id);
      if (!mounted) return;
      context.go('/circles');
    } catch (e, st) {
      debugPrint('Leave circle failed: $e');
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not leave: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  Future<void> _removeMember(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove member'),
        content: const Text('Remove this member from the circle?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Circles.removeMember(widget.circleId, userId);
      await _load();
    } catch (e, st) {
      debugPrint('Remove member failed: $e');
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  Future<void> _deleteCircle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete circle'),
        content: Text('Delete ${_circle?.name ?? 'this circle'} and its data?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || _circle == null) return;
    try {
      await Circles.deleteCircle(_circle!.id);
      if (!mounted) return;
      context.go('/circles');
    } catch (e, st) {
      debugPrint('Delete circle failed: $e');
      await Sentry.captureException(e, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: _circle?.name ?? 'Circle',
      subtitle: _isAdmin ? 'You manage this circle' : null,
      navIndex: 2,
      actions: [
        if (_isAdmin)
          IconButton(
            tooltip: 'Invite member',
            icon: const Icon(Icons.person_add_outlined),
            onPressed: _inviteMember,
          ),
        PopupMenuButton<String>(
          tooltip: 'Circle actions',
          onSelected: (value) {
            if (value == 'leave') _leaveCircle();
            if (value == 'delete') _deleteCircle();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'leave', child: Text('Leave circle')),
            if (_isAdmin)
              const PopupMenuItem(value: 'delete', child: Text('Delete circle')),
          ],
        ),
      ],
      body: _isLoading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(
                  title: "We couldn't load this circle",
                  detail: friendlyErrorMessage(_error, fallback: kLoadFailedDetail),
                  onRetry: _load,
                )
              : _circle == null
                  ? const Center(child: Text('Circle not found'))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        _CircleHeader(circle: _circle!),
                        if (_invites.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                            child: Text('Pending invitations',
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                          for (final invite in _invites)
                            ListTile(
                              leading: const Icon(Icons.mail_outline),
                              title: Text(invite['invitee_name'] as String? ?? 'Invitee'),
                              trailing: TextButton(
                                onPressed: () =>
                                    _respondToInvite(invite['invite_id'] as String, false),
                                child: const Text('Cancel invite'),
                              ),
                            ),
                        ],
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: Text('Members (${_members.length})',
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        if (_members.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No members yet'),
                          )
                        else
                          for (final member in _members)
                            _MemberTile(
                              member: member,
                              isAdmin: _isAdmin,
                              onRemove: () => _removeMember(member.userId),
                            ),
                      ],
                    ),
    );
  }
}

class _CircleHeader extends StatelessWidget {
  final Circle circle;
  const _CircleHeader({required this.circle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: app_colors.P.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: app_colors.P.border.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: app_colors.P.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                _initials(circle.name),
                style: const TextStyle(
                  color: app_colors.P.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(circle.name,
                    style: const TextStyle(
                        color: app_colors.P.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                if (circle.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(circle.description!,
                      style: const TextStyle(color: app_colors.P.muted, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Text(
                  '${circle.memberCount} members  |  ${circle.isPrivate ? 'Private' : 'Public'}',
                  style: const TextStyle(color: app_colors.P.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final CircleMember member;
  final bool isAdmin;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.isAdmin,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final me = Supa.currentUser?.id == member.userId;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: app_colors.P.surfaceHigh,
        foregroundColor: app_colors.P.primary,
        child: Text(_initials(member.displayName)),
      ),
      title: Text(member.displayName,
          style: const TextStyle(color: app_colors.P.text)),
      subtitle: Text('@${member.username}',
          style: const TextStyle(color: app_colors.P.muted, fontSize: 12)),
      trailing: me
          ? const Text('You',
              style: TextStyle(color: app_colors.P.primary, fontSize: 12))
          : isAdmin && !member.isAdmin
              ? IconButton(
                  tooltip: 'Remove member',
                  icon: const Icon(Icons.person_remove_outlined,
                      color: Colors.redAccent),
                  onPressed: onRemove,
                )
              : member.isAdmin
                  ? const Icon(Icons.shield_outlined,
                      size: 18, color: app_colors.P.muted)
                  : null,
    );
  }
}

class _UserPickerDialog extends StatefulWidget {
  const _UserPickerDialog();

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  final _controller = TextEditingController();
  List<Profile> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final term = _controller.text.trim();
    if (term.isEmpty) return;
    setState(() => _searching = true);
    try {
      final rows = await Supa.searchUsers(term, limit: 6);
      if (mounted) setState(() => _results = rows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite member'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Username or name',
                hintText: 'Search for a person',
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search'),
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final profile = _results[i];
                    return ListTile(
                      key: ValueKey(profile.id),
                      leading: CircleAvatar(
                        backgroundColor: app_colors.P.surfaceHigh,
                        child: Text(_initials(profile.label)),
                      ),
                      title: Text(profile.label),
                      onTap: () => Navigator.pop(context, profile),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}
