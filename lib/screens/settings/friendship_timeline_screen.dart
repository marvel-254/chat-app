import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/friendship_timeline.dart';
import '../../models/profile.dart';
import '../../services/friendship_timeline.dart';
import '../../services/supabase.dart';
import '../../theme/app_colors.dart' as app_colors;
import '../../ui/errors.dart';
import '../../ui/motion.dart';
import '../../ui/states.dart';
import '../chat/widgets/avatar.dart';
import '../../widgets/responsive_app_shell.dart';

class _P {
  static const surface = app_colors.surface;
  static const surfaceHigh = app_colors.surfaceHigh;
  static const border = app_colors.border;
  static const text = app_colors.text;
  static const muted = app_colors.muted;
  static const primary = app_colors.volt;
  static const darkOnAccent = app_colors.darkOnVolt;
}

/// A private timeline between two friends: shared photos, important dates,
/// the first message, and pinned moments.
class FriendshipTimelineScreen extends StatefulWidget {
  const FriendshipTimelineScreen({
    super.key,
    required this.peerId,
    this.peer,
  });

  final String peerId;
  final Profile? peer;

  @override
  State<FriendshipTimelineScreen> createState() =>
      _FriendshipTimelineScreenState();
}

class _FriendshipTimelineScreenState extends State<FriendshipTimelineScreen> {
  late Future<List<FriendshipTimelineEntry>> _entries;
  Profile? _peer;
  final _dateTitle = TextEditingController();
  bool _remindAnnually = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _peer = widget.peer;
    _entries = FriendshipTimelineService.load(widget.peerId);
    if (widget.peer == null) {
      Supa.getProfile(widget.peerId).then((profile) {
        if (mounted && profile != null) setState(() => _peer = profile);
      });
    }
  }

  @override
  void dispose() {
    _dateTitle.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _entries = FriendshipTimelineService.load(widget.peerId));
  }

  Future<void> _pickPhoto() async {
    if (_busy) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (file == null) return;
      final caption = await _askCaption();
      if (caption == null) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      await FriendshipTimelineService.addPhoto(
        widget.peerId,
        bytes: await file.readAsBytes(),
        filename: file.name,
        caption: caption,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e,
          fallback: "We couldn't add that photo. Try another one."));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns the caption, or null when the user cancelled.
  Future<String?> _askCaption() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _P.surface,
        title: const Text('Add a caption',
            style: TextStyle(color: _P.text, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 140,
          style: const TextStyle(color: _P.text),
          decoration: const InputDecoration(
            hintText: 'Optional — a memory goes here',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Skip'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _P.primary,
              foregroundColor: _P.darkOnAccent,
            ),
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Add photo'),
          ),
        ],
      ),
    );
  }

  Future<void> _addDate() async {
    if (_busy) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: _P.primary,
                onPrimary: _P.darkOnAccent,
                surface: _P.surface,
              ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final title = await _askDateTitle(picked);
    if (title == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FriendshipTimelineService.addDate(
        widget.peerId,
        title: title,
        occursOn: picked,
        remindAnnually: _remindAnnually,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e,
          fallback: "We couldn't save that date. Try again."));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askDateTitle(DateTime picked) {
    _dateTitle.clear();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: _P.surface,
          title: const Text('Important date',
              style: TextStyle(color: _P.text, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _dateTitle,
                autofocus: true,
                maxLength: 120,
                style: const TextStyle(color: _P.text),
                decoration: const InputDecoration(
                  hintText: 'Birthday, anniversary, the day we met…',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember every year',
                    style: TextStyle(color: _P.text, fontSize: 14)),
                value: _remindAnnually,
                activeThumbColor: _P.primary,
                onChanged: (value) =>
                    setDialogState(() => _remindAnnually = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _P.primary,
                foregroundColor: _P.darkOnAccent,
              ),
              onPressed: () {
                final value = _dateTitle.text.trim();
                Navigator.pop(dialogContext, value.isEmpty ? null : value);
              },
              child: const Text('Save date'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(FriendshipTimelineEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _P.surface,
        title: const Text('Remove from timeline?',
            style: TextStyle(color: _P.text, fontSize: 17)),
        content: Text(
          entry.isPhoto
              ? 'This photo disappears for both of you.'
              : 'This date disappears for both of you.',
          style: const TextStyle(color: _P.muted, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: _P.primary),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (entry.isPhoto) {
        await FriendshipTimelineService.removePhoto(FriendshipPhoto(
          id: entry.id,
          conversationId: entry.conversationId,
          objectPath: entry.photoPath ?? '',
          createdAt: entry.createdAt,
        ));
      } else if (entry.isDate) {
        await FriendshipTimelineService.removeDate(FriendshipDate(
          id: entry.id,
          conversationId: entry.conversationId,
          title: entry.dateTitle ?? '',
          occursOn: entry.occursOn ?? entry.createdAt,
          remindAnnually: entry.remindAnnually ?? true,
          createdAt: entry.createdAt,
        ));
      }
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(e,
          fallback: "That didn't come off. Try again."));
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = _peer;
    return ResponsiveAppShell(
      title: 'Friendship timeline',
      subtitle: peer == null ? 'Your story together' : 'With ${peer.label}',
      navIndex: 0,
      showBottomNavigation: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: [
        IconButton(
          tooltip: 'Add important date',
          onPressed: _busy ? null : _addDate,
          icon: const Icon(Icons.event_outlined, color: _P.primary),
        ),
        IconButton(
          tooltip: 'Add photo',
          onPressed: _busy ? null : _pickPhoto,
          icon: _busy
              ? const BroSpinner(size: 18)
              : const Icon(Icons.add_photo_alternate_outlined,
                  color: _P.primary),
        ),
      ],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Avatar(
                      name: peer?.peerInitial ?? '?',
                      url: peer?.avatarUrl,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        peer == null
                            ? 'Shared moments, dates, and the first message.'
                            : 'Photos, dates, and moments you and ${peer.label} keep together.',
                        style: const TextStyle(
                            color: _P.muted, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SoftErrorBanner(message: _error!),
                ),
              Expanded(
                child: FutureBuilder<List<FriendshipTimelineEntry>>(
                  future: _entries,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const ListSkeleton(label: 'Loading your timeline');
                    }
                    if (snapshot.hasError) {
                      return AppErrorState(
                        title: "Your timeline didn't load",
                        detail: friendlyErrorMessage(snapshot.error,
                            fallback:
                                'Give it another try — it usually comes right back.'),
                        onRetry: _reload,
                      );
                    }
                    final entries = snapshot.data ?? const [];
                    if (entries.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.auto_awesome_outlined,
                        title: 'No memories yet',
                        subtitle:
                            'Add the first photo or an important date, then pin a message in your chat to keep it here.',
                        action: FilledButton.tonalIcon(
                          onPressed: _pickPhoto,
                          style: FilledButton.styleFrom(
                            backgroundColor: _P.surface,
                            foregroundColor: _P.primary,
                          ),
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 18),
                          label: const Text('Add a photo'),
                        ),
                      );
                    }
                    return RefreshIndicator(
                      color: _P.primary,
                      backgroundColor: _P.surface,
                      onRefresh: () async {
                        _reload();
                        await Future<void>.delayed(
                            const Duration(milliseconds: 400));
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
                        itemCount: entries.length,
                        itemBuilder: (context, index) => FadeSlideIn(
                          index: index.clamp(0, 8),
                          child: _TimelineTile(
                            entry: entries[index],
                            myId: Supa.currentUser?.id ?? '',
                            onRemove: () => _confirmRemove(entries[index]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.entry,
    required this.myId,
    required this.onRemove,
  });

  final FriendshipTimelineEntry entry;
  final String myId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _P.border.withValues(alpha: 0.28)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TimelineRail(entry: entry),
              const SizedBox(width: 14),
              Expanded(child: _content(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (entry.isPhoto) {
      return _PhotoContent(entry: entry, onRemove: onRemove);
    }
    final title = entry.isDate
        ? (entry.dateTitle ?? 'Important date')
        : (entry.momentPreview ?? '');
    final subtitle = entry.isDate
        ? 'Added ${_formatDate(entry.createdAt)}'
        : entry.isFirstMessage
            ? 'Where it all started · ${_formatDate(entry.createdAt)}'
            : 'Pinned · ${_formatDate(entry.momentPinnedAt ?? entry.createdAt)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.trim().isEmpty ? 'Memory' : title.trim(),
          style: const TextStyle(
              color: _P.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: _P.muted, fontSize: 12.5),
        ),
        if (entry.momentSenderId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              entry.momentSenderId == myId ? 'From you' : 'From your friend',
              style: const TextStyle(
                  color: _P.muted, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

class _TimelineRail extends StatelessWidget {
  const _TimelineRail({required this.entry});

  final FriendshipTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, dayLabel) = switch (entry.kind) {
      FriendshipTimelineEntry.kindPhoto => (
          Icons.photo_outlined,
          _monthDay(entry.createdAt)
        ),
      FriendshipTimelineEntry.kindDate => (
          Icons.event_outlined,
          entry.occursOn == null
              ? 'Date'
              : _FriendshipDateLabel.dayLabel(entry.occursOn!)
        ),
      FriendshipTimelineEntry.kindFirstMessage => (
          Icons.flag_outlined,
          _monthDay(entry.createdAt)
        ),
      _ => (Icons.push_pin_outlined, _monthDay(entry.createdAt)),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _P.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: _P.primary.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 18, color: _P.primary),
        ),
        const SizedBox(height: 5),
        Text(
          dayLabel,
          style: const TextStyle(
              color: _P.muted, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  static String _monthDay(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}';
  }
}

/// A shared photo plus its caption. Tapping opens the full-screen viewer.
class _PhotoContent extends StatelessWidget {
  const _PhotoContent({required this.entry, required this.onRemove});

  final FriendshipTimelineEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final caption = entry.photoCaption?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<String>(
          future: Supa.attachmentUrl(entry.photoPath ?? ''),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                height: 160,
                decoration: BoxDecoration(
                  color: _P.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(child: BroSpinner(size: 20)),
              );
            }
            if (snapshot.hasError) {
              return Container(
                height: 100,
                decoration: BoxDecoration(
                  color: _P.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, color: _P.muted),
                ),
              );
            }
            return GestureDetector(
              onTap: () => _openViewer(context, snapshot.data!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  snapshot.data!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: _P.surfaceHigh,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, color: _P.muted),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            style: const TextStyle(color: _P.text, fontSize: 14, height: 1.4),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _FriendshipDateLabel.formatDate(entry.createdAt),
              style: const TextStyle(color: _P.muted, fontSize: 12),
            ),
            const Spacer(),
            if (entry.photoMessageId == null)
              IconButton(
                tooltip: 'Remove photo',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon:
                    const Icon(Icons.delete_outline, size: 18, color: _P.muted),
              ),
          ],
        ),
      ],
    );
  }

  void _openViewer(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black.withValues(alpha: 0.95),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 4.0,
              child: Center(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 24,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small helpers shared by the rail and the photo card.
class _FriendshipDateLabel {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String dayLabel(DateTime value) =>
      '${value.day} ${_months[value.month - 1]}';

  static String formatDate(DateTime value) =>
      '${_months[value.month - 1]} ${value.day}, ${value.year}';
}
