import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../models/circle.dart';
import '../services/circles.dart';
import '../services/supabase.dart';

class CircleDetailScreen extends StatefulWidget {
  final String circleId;

  const CircleDetailScreen({super.key, required this.circleId});

  @override
  State<CircleDetailScreen> createState() => _CircleDetailScreenState();
}

class _CircleDetailScreenState extends State<CircleDetailScreen> {
  Circle? _circle;
  List<CircleMember> _members = [];
  bool _isLoading = true;
  String? _error;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadCircle();
  }

  Future<void> _loadCircle() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all circles and filter client-side since RPC doesn't support .eq() filtering
      final circles = await Circles.getAllCircles();
      final circle = circles.firstWhere(
        (c) => c.id == widget.circleId,
        orElse: () => throw 'Circle not found',
      );

      final members = await Circles.getCircleMembers(widget.circleId);
      final isAdmin = await Circles.isAdmin(widget.circleId);

      setState(() {
        _circle = circle;
        _members = members;
        _isAdmin = isAdmin;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('Failed to load circle: $e');
      Sentry.captureException(e, stackTrace: st);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _leaveCircle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Circle'),
        content: Text('Are you sure you want to leave "${_circle?.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && _circle != null) {
      try {
        await Circles.leave(_circle!.id);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Left circle')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to leave: $e')),
        );
      }
    }
  }

  Future<void> _inviteMember() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite Member'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Enter username to invite',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.none,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Invite'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      // Search for user by username
      if (!mounted) return;
      final profiles = await Supa.searchUsers(result);
      if (!mounted) return;
      if (profiles.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not found')),
        );
        return;
      }

      final user = profiles.first;
      try {
        // Note: join_circle uses auth.uid() server-side, so it only joins
        // the current user. To invite another user, the server would need
        // a separate invite function. For now, just show a message.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'User "$user.username" found — direct messaging them instead')),
        );
        if (!mounted) return;
        final conv = await Supa.getOrCreateDM(user.id);
        if (!mounted) return;
        context.go('/chat/${conv.id}', extra: user);
        return;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: const Text('Are you sure you want to remove this member?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supa.client
            .from('circle_participants')
            .delete()
            .eq('circle_id', widget.circleId)
            .eq('user_id', userId);
        setState(() => _loadCircle());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member removed')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121318),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1F25),
        title: Text(_circle?.name ?? 'Circle'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: _inviteMember,
              tooltip: 'Invite Member',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'leave') _leaveCircle();
              if (value == 'delete') _deleteCircle();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave Circle'),
              ),
              if (_isAdmin)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete Circle',
                      style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_error ?? 'Unknown error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadCircle,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _circle == null
                  ? const Center(child: Text('Circle not found'))
                  : Column(
                      children: [
                        _CircleHeader(circle: _circle!),
                        const Divider(height: 1, color: Color(0xFF444932)),
                        Expanded(
                          child: _MembersList(
                            members: _members,
                            isAdmin: _isAdmin,
                            currentUserId: Supa.client.auth.currentUser?.id,
                            onRemove: _removeMember,
                          ),
                        ),
                      ],
                    ),
    );
  }

  Future<void> _deleteCircle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Circle'),
        content: Text(
            'This will delete "${_circle?.name}" and all its data. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && _circle != null) {
      try {
        await Circles.deleteCircle(_circle!.id);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Circle deleted')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}

class _CircleHeader extends StatelessWidget {
  final Circle circle;

  const _CircleHeader({required this.circle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF2A2B30),
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF363740),
                  const Color(0xFF292A2F),
                ],
              ),
            ),
            child: Center(
              child: Text(
                _getInitials(circle.name),
                style: const TextStyle(
                  color: Color(0xFFE3E1E9),
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            circle.name,
            style: const TextStyle(
              color: Color(0xFFE3E1E9),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (circle.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              circle.description ?? '',
              style: const TextStyle(
                color: Color(0xFFC5C9AC),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                '${circle.memberCount} members',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                circle.isPrivate ? Icons.lock : Icons.public,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                circle.isPrivate ? 'Private' : 'Public',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 2).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _MembersList extends StatelessWidget {
  final List<CircleMember> members;
  final bool isAdmin;
  final String? currentUserId;
  final Function(String) onRemove;

  const _MembersList({
    required this.members,
    required this.isAdmin,
    required this.currentUserId,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(
        child: Text(
          'No members yet',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: members.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: Color(0xFF444932),
      ),
      itemBuilder: (context, index) {
        final member = members[index];
        final userId = member.userId;
        final isCurrentUser = userId == currentUserId;
        final isMemberAdmin = member.isAdmin;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF2A2B30),
            child: Text(
              _getInitials(member.displayName),
              style: const TextStyle(
                color: Color(0xFFE3E1E9),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            member.displayName,
            style: const TextStyle(
              color: Color(0xFFE3E1E9),
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            '@${member.username}',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
            ),
          ),
          trailing: isCurrentUser
              ? const Text(
                  'You',
                  style: TextStyle(
                    color: Color(0xFFD4FF00),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                )
              : isAdmin && !isMemberAdmin
                  ? IconButton(
                      icon: const Icon(
                        Icons.person_remove,
                        color: Colors.red,
                      ),
                      onPressed: () => onRemove(userId),
                      tooltip: 'Remove member',
                    )
                  : null,
        );
      },
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 2).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
