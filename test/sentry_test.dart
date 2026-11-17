import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/widgets/sentry_test_button.dart';

void main() {
  testWidgets('SentryTestButton builds and can be pressed', (WidgetTester tester) async {
    // Build our widget.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SentryTestButton(),
        ),
      ),
    );

    // Verify that the button is rendered with the correct label.
    expect(find.text('Break the world'), findsOneWidget);
    
    // Verify the button is tappable.
    final button = find.byType(ElevatedButton);
    expect(button, findsOneWidget);
  });
}
