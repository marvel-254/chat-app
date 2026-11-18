import 'package:flutter/material.dart';

import '../services/people_search_history.dart';
import '../theme/app_colors.dart' as colors;

/// Appears beneath a focused, empty people search field.
class RecentPeopleSearches extends StatelessWidget {
  const RecentPeopleSearches({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.accountId,
    required this.onSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? Function() accountId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, focusNode]),
          builder: (context, _) {
            if (!focusNode.hasFocus || controller.text.trim().isNotEmpty) {
              return const SizedBox.shrink();
            }
            final owner = accountId();
            if (owner == null) return const SizedBox.shrink();
            return _RecentSearchList(
              key: ValueKey(owner),
              owner: owner,
              isActive: () => accountId() == owner,
              onSelected: onSelected,
            );
          },
        ),
      );
}

class _RecentSearchList extends StatefulWidget {
  const _RecentSearchList({
    super.key,
    required this.owner,
    required this.isActive,
    required this.onSelected,
  });

  final String owner;
  final bool Function() isActive;
  final ValueChanged<String> onSelected;

  @override
  State<_RecentSearchList> createState() => _RecentSearchListState();
}

class _RecentSearchListState extends State<_RecentSearchList> {
  late Future<List<String>> _history = PeopleSearchHistory.load(widget.owner);

  Future<void> _clear() async {
    if (!widget.isActive()) return;
    try {
      await PeopleSearchHistory.clear(widget.owner);
      if (mounted) {
        setState(() {
          _history = Future.value(const <String>[]);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't clear recent searches.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
        future: _history,
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (!widget.isActive() || entries == null || entries.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Recent searches',
                        style: TextStyle(
                            color: colors.muted, fontWeight: FontWeight.w600)),
                    TextButton(
                        onPressed: _clear, child: const Text('Clear all')),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.history, size: 16),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 190),
                              child:
                                  Text(entry, overflow: TextOverflow.ellipsis),
                            ),
                            onPressed: () {
                              if (widget.isActive()) widget.onSelected(entry);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}
