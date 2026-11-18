import 'package:flutter/material.dart';
import '../ui/states.dart';
import '../ui/motion.dart';
import '../models/circle.dart';
import '../services/circles.dart';
import '../widgets/responsive_app_shell.dart';
import 'circle_detail_screen.dart';

class CirclesScreen extends StatefulWidget {
  const CirclesScreen({super.key});

  @override
  State<CirclesScreen> createState() => _CirclesScreenState();
}

class _CirclesScreenState extends State<CirclesScreen> {
  final _scrollController = ScrollController();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addMemberController = TextEditingController();

  bool _isLoading = true;
  List<Circle> _circles = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCircles();
    Circles.watchMyCircles().listen((circles) {
      setState(() {
        _circles = circles;
        _isLoading = false;
      });
    }).onError((e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    });
  }

  Future<void> _loadCircles() async {
    setState(() => _isLoading = true);
    try {
      final circles = await Circles.getAllCircles();
      if (!mounted) return;
      setState(() {
        _circles = circles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createCircle() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a circle name')),
      );
      return;
    }

    try {
      final circleId = await Circles.create(
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

      await Circles.join(circleId);

      await Circles.linkConversation(circleId, circleId);

      setState(() {
        _nameController.clear();
        _descriptionController.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Circle created!')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create circle: $e')),
      );
    }
  }

  Future<void> _deleteCircle(String circleId, String circleName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Circle'),
        content: Text('Are you sure you want to delete "$circleName"?'),
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

    if (confirmed == true) {
      try {
        await Circles.deleteCircle(circleId);
        setState(() {
          _circles.removeWhere((c) => c.id == circleId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Circle deleted')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete circle: $e')),
        );
      }
    }
  }

  void _showCreateCircleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Circle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Circle Name *',
                  hintText: 'e.g., Work Friends, Gaming Squad',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What is this circle about?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _createCircle();
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _addMemberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: 'Circles',
      subtitle: 'Small groups for the people who matter',
      navIndex: 1,
      actions: [
        IconButton(
          tooltip: 'Create circle',
          icon: const Icon(Icons.add),
          onPressed: _showCreateCircleDialog,
        ),
      ],
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: _isLoading
                ? const AppLoader()
                : _error != null
                    ? AppErrorState(
                        title: "We couldn't load your circles",
                        detail: _error,
                        onRetry: _loadCircles,
                      )
                    : _circles.isEmpty
                        ? AppEmptyState(
                            icon: Icons.groups_rounded,
                            title: 'No circles yet',
                            subtitle: 'Create your first circle to get started',
                            action: FilledButton(
                              onPressed: _showCreateCircleDialog,
                              child: const Text('Create circle'),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your Circles (${_circles.length})',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _circles.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final circle = _circles[index];
                                    return FadeSlideIn(
                                      index: index.clamp(0, 8),
                                      child: PressScale(
                                        scaleFactor: 0.98,
                                        child: _CirclesCard(
                                          circle: circle,
                                          onEdit: () =>
                                              _showEditCircleDialog(circle),
                                          onDelete: () => _deleteCircle(
                                              circle.id, circle.name),
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CircleDetailScreen(
                                                      circleId: circle.id),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  void _showEditCircleDialog(Circle circle) {
    final nameController = TextEditingController(text: circle.name);
    final descriptionController =
        TextEditingController(text: circle.description ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Circle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Circle Name *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              nameController.dispose();
              descriptionController.dispose();
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              nameController.dispose();
              descriptionController.dispose();
              Navigator.pop(context);
              if (name.isEmpty) return;
              await Circles.updateCircle(
                circle.id,
                name: name,
                description: description.isEmpty ? null : description,
              );
              await _loadCircles();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _CirclesCard extends StatelessWidget {
  final Circle circle;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CirclesCard({
    required this.circle,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1F25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF444932),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2B30),
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF363740),
                    Color(0xFF292A2F),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  getInitials(circle.name),
                  style: const TextStyle(
                    color: Color(0xFFE3E1E9),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    circle.name,
                    style: const TextStyle(
                      color: Color(0xFFE3E1E9),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (circle.description?.isNotEmpty == true)
                    Text(
                      circle.description ?? '',
                      style: const TextStyle(
                        color: Color(0xFFC5C9AC),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.people,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${circle.memberCount} members',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (circle.isMember == false)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4FF00),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Request Sent',
                            style: TextStyle(
                              color: Color(0xFF0C0D12),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 2).toUpperCase();
    return parts[0][0].toUpperCase() + parts[1][0].toUpperCase();
  }
}
