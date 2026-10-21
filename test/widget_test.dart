import 'package:flutter_test/flutter_test.dart';

import 'package:pulse_chat/main.dart';

void main() {
  testWidgets('Chat screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PulseChatApp());
    expect(find.text('Pulse'), findsWidgets);
  });
}
