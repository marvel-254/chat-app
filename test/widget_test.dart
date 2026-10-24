import 'package:flutter_test/flutter_test.dart';

import 'package:vantastic/main.dart';

void main() {
  testWidgets('Chat screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const NYXApp());
    expect(find.text('NYX'), findsWidgets);
  });
}