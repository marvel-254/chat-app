import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:nyx_chat/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Supabase.initialize persists the session via SharedPreferences, which
    // has no platform implementation in widget tests. Stub the method channel
    // so initialize() succeeds without a real backend.
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAll':
          return <String, Object>{};
        case 'setString':
        case 'remove':
        case 'clear':
          return true;
        default:
          return null;
      }
    });

    await Supabase.initialize(
      url: 'https://dummy.example.supabase.co',
      publishableKey: 'dummy-anon-key-for-tests',
    );
  });

  testWidgets('App boots to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BroApp());
    await tester.pump(); // let the auth stream resolve to "no session"
    // With the dummy config there is no session, so AuthGate shows LoginScreen,
    // whose welcome heading proves the app tree rendered without a live backend.
    expect(find.text('Good to see you, Bro.'), findsOneWidget);
    expect(find.text('Hey, Bro! 👋'), findsNothing);
    expect(find.text('Start with your email'), findsNothing);

    final emailInput = find.byType(TextField).first;
    final passwordInput = find.byType(TextField).last;
    Container inputContainer(Finder field) => tester.widget<Container>(
          find
              .ancestor(of: field, matching: find.byType(Container))
              .first,
        );
    Color borderColor(Finder field) =>
        ((inputContainer(field).decoration! as BoxDecoration).border! as Border)
            .top
            .color;

    expect(borderColor(emailInput), const Color(0xFFD4FF00));
    await tester.tap(passwordInput);
    await tester.pump(const Duration(milliseconds: 300));
    expect(borderColor(passwordInput), const Color(0xFFD4FF00));
    expect(borderColor(emailInput), isNot(const Color(0xFFD4FF00)));
  });
}