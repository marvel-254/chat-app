import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/screens/navigation/nav_sidebar.dart';
import 'package:bro_chat/services/calls.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('NavSidebar builds without a GoRouterState ancestor',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              NavSidebar(),
              Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  test('Calls classifies JWT expired and timeout errors as transient', () {
    expect(
      Calls.isJwtExpiredError(
        const PostgrestException(message: 'JWT expired', code: 'PGRST303'),
      ),
      isTrue,
    );
    expect(
      Calls.isJwtExpiredError(
        const PostgrestException(message: 'other error', code: '42501'),
      ),
      isFalse,
    );
    expect(
      Calls.isTransientNetworkError(TimeoutException('timed out')),
      isTrue,
    );
    expect(
      Calls.isTransientNetworkError(StateError('unexpected')),
      isFalse,
    );
  });
}
