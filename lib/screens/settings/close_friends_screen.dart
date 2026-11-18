import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/supabase.dart';
import '../chat/widgets/avatar.dart';
import '../../widgets/responsive_app_shell.dart';

class CloseFriendsScreen extends StatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  State<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends State<CloseFriendsScreen> {
  final _search = TextEditingController();
  late Future<List<Profile>> _people;
  Set<String> _selected = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _people = _loadPeople();
  }

  Future<List<Profile>> _loadPeople() async {
    final results = await Future.wait([
      Supa.searchUsers(''),
      Supa.getCloseFriendIds(),
    ]);
    _selected = Set<String>.from(results[1] as List<String>);
    return results[0] as List<Profile>;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _toggle(Profile person) async {
    final next = !_selected.contains(person.id);
    setState(() {
      if (next) {
        _selected = {..._selected, person.id};
      } else {
        _selected = {..._selected}..remove(person.id);
      }
    });
    try {
      await Supa.setCloseFriend(person.id, next);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (next) {
          _selected = {..._selected}..remove(person.id);
        } else {
          _selected = {..._selected, person.id};
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update close friends.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAppShell(
      title: 'Close friends',
      navIndex: 0,
      showBottomNavigation: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FutureBuilder<List<Profile>>(
            future: _people,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () => setState(() => _people = _loadPeople()),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                );
              }
              final people = (snapshot.data ?? const <Profile>[])
                  .where((person) => person.id != Supa.currentUser?.id)
                  .where((person) {
                final query = _query.trim().toLowerCase();
                if (query.isEmpty) return true;
                return person.label.toLowerCase().contains(query) ||
                    person.username.toLowerCase().contains(query);
              }).toList();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search people',
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Only people you choose can see statuses shared with close friends.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  Expanded(
                    child: people.isEmpty
                        ? const Center(child: Text('No people found'))
                        : ListView.builder(
                            itemCount: people.length,
                            itemBuilder: (_, index) {
                              final person = people[index];
                              final selected = _selected.contains(person.id);
                              return ListTile(
                                leading: Avatar(
                                  name: person.peerInitial,
                                  url: person.avatarUrl,
                                  size: 44,
                                ),
                                title: Text(person.label),
                                subtitle: Text('@${person.username}'),
                                trailing: Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggle(person),
                                ),
                                onTap: () => _toggle(person),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
