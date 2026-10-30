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
  });
}