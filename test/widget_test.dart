import 'package:flutter_test/flutter_test.dart';

import 'package:vantastic/main.dart';

void main() {
  testWidgets('Chat screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const VantasticApp());
    expect(find.text('Vantastic'), findsWidgets);
  });
}