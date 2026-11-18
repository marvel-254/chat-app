import 'dart:async';

import 'package:bro_chat/models/profile.dart';
import 'package:bro_chat/screens/chat/suggest_friends_screen.dart';
import 'package:bro_chat/services/people_search_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FriendSuggestion _suggestion(String username) => FriendSuggestion(
      userId: username,
      username: username,
      isOnline: false,
      mutualCount: 0,
      suggestionReason: '',
      suggestionType: '',
      isFollowing: false,
      isCloseFriend: false,
    );

String? _noAccount() => null;

void main() {
  testWidgets('refresh fetches again even when the category was empty',
      (tester) async {
    final requests = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SuggestFriendsScreen(
        recentSearchAccountId: _noAccount,
        loadSuggestions: (category) async {
          requests.add(category);
          return requests.length == 1 ? [] : [_suggestion('newfriend')];
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No suggestions yet'), findsOneWidget);

    await tester.drag(
      find.byKey(const PageStorageKey('suggestions-all')),
      const Offset(0, 350),
    );
    await tester.pumpAndSettle();

    expect(requests, ['all', 'all']);
    expect(find.text('@newfriend'), findsOneWidget);
  });

  testWidgets('failed load has a retry instead of an empty state',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
      home: SuggestFriendsScreen(
        recentSearchAccountId: _noAccount,
        loadSuggestions: (_) async {
          if (++requests == 1) throw StateError('Offline');
          return [_suggestion('recovered')];
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No suggestions yet'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('@recovered'), findsOneWidget);
  });

  testWidgets('long search results scroll in a short phone viewport',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final profiles = List.generate(
      20,
      (index) => Profile.fromJson({
        'id': '$index',
        'username': 'person$index',
        'created_at': '2026-11-18T00:00:00Z',
        'updated_at': '2026-11-18T00:00:00Z',
      }),
    );
    await tester.pumpWidget(MaterialApp(
      home: SuggestFriendsScreen(
        recentSearchAccountId: _noAccount,
        loadSuggestions: (_) async => [],
        searchUsers: (_) async => profiles,
        getFollowedUserIds: (_) async => <String>{},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'person');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('@person0'), findsOneWidget);

    final results = find.byKey(const ValueKey('people-search-results'));
    await tester.scrollUntilVisible(
      find.text('@person19'),
      300,
      scrollable: find.descendant(
        of: results,
        matching: find.byType(Scrollable),
      ),
    );
    // Allow staggered tile animations to finish after the last scroll.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('@person19').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search shows current follow status and syncs category tiles',
      (tester) async {
    final changes = <bool>[];
    final profile = Profile.fromJson({
      'id': 'existing',
      'username': 'existing',
      'created_at': '2026-11-18T00:00:00Z',
      'updated_at': '2026-11-18T00:00:00Z',
    });
    await tester.pumpWidget(MaterialApp(
      home: SuggestFriendsScreen(
        recentSearchAccountId: _noAccount,
        loadSuggestions: (_) async =>
            [_suggestion('existing').withFollowing(true)],
        searchUsers: (_) async => [profile],
        getFollowedUserIds: (ids) async {
          expect(ids, ['existing']);
          return {'existing'};
        },
        setFollowing: (id, following) async {
          expect(id, 'existing');
          changes.add(following);
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'existing');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Following'), findsOneWidget);

    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(changes, [false]);
    expect(find.text('Follow'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('Following'), findsNothing);
  });

  testWidgets('people appear before follow status and survive lookup failure',
      (tester) async {
    final followStatus = Completer<Set<String>>();
    var lookups = 0;
    final profile = Profile.fromJson({
      'id': 'alex',
      'username': 'alex',
      'created_at': '2026-11-18T00:00:00Z',
      'updated_at': '2026-11-18T00:00:00Z',
    });
    await tester.pumpWidget(MaterialApp(
      home: SuggestFriendsScreen(
        recentSearchAccountId: _noAccount,
        loadSuggestions: (_) async => [],
        searchUsers: (_) async => [profile],
        getFollowedUserIds: (_) async {
          if (++lookups == 1) return followStatus.future;
          return {'alex'};
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '@alex');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final person = find.descendant(
      of: find.byKey(const ValueKey('people-search-results')),
      matching: find.text('@alex'),
    );
    expect(person, findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Follow'), findsNothing);

    followStatus.completeError(StateError('Follow lookup failed'));
    await tester.pumpAndSettle();
    expect(person, findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(person, findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('recent searches can be replayed and cleared', (tester) async {
    SharedPreferences.setMockInitialValues({
      'bro.people_search_history.v1.alice': ['@alex'],
    });
    final queries = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: SuggestFriendsScreen(
        recentSearchAccountId: () => 'alice',
        loadSuggestions: (_) async => [],
        searchUsers: (query) async {
          queries.add(query);
          return [];
        },
      ),
    ));
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsOneWidget);
    final chip = find.widgetWithText(ActionChip, '@alex');
    tester.widget<ActionChip>(chip).onPressed!();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(queries, ['@alex']);
    expect(tester.widget<TextField>(field).controller!.text, '@alex');

    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    final clear = find.widgetWithText(TextButton, 'Clear all');
    tester.widget<TextButton>(clear).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Recent searches'), findsNothing);
    expect(await PeopleSearchHistory.load('alice'), isEmpty);
  });
}
