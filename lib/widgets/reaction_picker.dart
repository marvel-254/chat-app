import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/supabase.dart';

/// Emoji categories with their representative emojis
const _emojiCategories = {
  'Frequent': ['👍', '❤️', '😂', '😮', '😢', '😡', '🎉', '🙏', '👏', '🔥'],
  'Reactions': ['👍', '👎', '❤️', '😂', '😮', '😢', '😡', '🎉', '🙏', '👏', '🔥', '💯', '🤝', '👌', '✨'],
  'Faces': ['😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '☺️', '😚', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺', '👻', '👽', '👾', '🤖', '😺', '😸', '😹', '😻', '😼', '😽', '🙀', '😿', '😾'],
  'Hands': ['👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '🤝', '🙏', '✍️', '💅', '🤲', '👐'],
};

class ReactionPicker extends StatefulWidget {
  final Message message;
  final List<Map<String, dynamic>> currentReactions;
  final VoidCallback onDismiss;
  final ValueChanged<String> onReactionSelected;

  const ReactionPicker({
    super.key,
    required this.message,
    required this.currentReactions,
    required this.onDismiss,
    required this.onReactionSelected,
  });

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'Frequent';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _emojiCategories.keys.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, int> get _reactionCounts {
    final counts = <String, int>{};
    for (final r in widget.currentReactions) {
      final emoji = r['emoji'] as String;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  bool _hasUserReacted(String emoji) {
    final me = Supa.currentUser;
    if (me == null) return false;
    return widget.currentReactions.any((r) => r['emoji'] == emoji && r['user_id'] == me.id);
  }

  @override
  Widget build(BuildContext context) {
    final counts = _reactionCounts;
    final categoryKeys = _emojiCategories.keys.toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          color: _P.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: _P.border.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _P.muted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Category tabs
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: _P.volt,
              unselectedLabelColor: _P.muted,
              indicatorColor: _P.volt,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              dividerColor: Colors.transparent,
              tabs: categoryKeys.map((c) => Tab(text: c)).toList(),
              onTap: (i) => setState(() => _selectedCategory = categoryKeys[i]),
            ),
            // Emoji grid
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: categoryKeys.map((category) {
                  final emojis = _emojiCategories[category]!;
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: emojis.length,
                    itemBuilder: (context, index) {
                      final emoji = emojis[index];
                      final count = counts[emoji] ?? 0;
                      final hasReacted = _hasUserReacted(emoji);
                      
                      return _EmojiButton(
                        emoji: emoji,
                        count: count,
                        hasReacted: hasReacted,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onReactionSelected(emoji);
                          widget.onDismiss();
                        },
                      );
                    },
                  );
                }).toList(),
              ),
            ),
            // Add custom reaction button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showCustomEmojiInput(context);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add custom emoji'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _P.muted,
                    side: BorderSide(color: _P.border.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomEmojiInput(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _P.surface,
        title: const Text('Custom Emoji'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2,
          decoration: const InputDecoration(
            hintText: 'Enter emoji',
            hintStyle: TextStyle(color: _P.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final emoji = controller.text.trim();
              if (emoji.isNotEmpty) {
                Navigator.pop(dialogContext);
                widget.onReactionSelected(emoji);
                widget.onDismiss();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _EmojiButton extends StatelessWidget {
  final String emoji;
  final int count;
  final bool hasReacted;
  final VoidCallback onTap;

  const _EmojiButton({
    required this.emoji,
    required this.count,
    required this.hasReacted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: hasReacted ? _P.volt.withValues(alpha: 0.2) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: hasReacted 
                ? Border.all(color: _P.volt, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              if (count > 0)
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: hasReacted ? _P.volt : _P.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the reaction picker as a bottom sheet
Future<void> showReactionPicker({
  required BuildContext context,
  required Message message,
  required List<Map<String, dynamic>> reactions,
  required ValueChanged<String> onReactionSelected,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => ReactionPicker(
      message: message,
      currentReactions: reactions,
      onDismiss: () => Navigator.pop(sheetContext),
      onReactionSelected: onReactionSelected,
    ),
  );
}