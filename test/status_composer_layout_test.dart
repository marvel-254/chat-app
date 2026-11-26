import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/screens/status_composer.dart';
import 'package:bro_chat/widgets/responsive_app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpComposer(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StatusComposerScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('composer uses the shared shell and fits compact screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpComposer(tester);

    expect(find.byType(ResponsiveAppShell), findsOneWidget);
    expect(find.text('Post'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox && widget.constraints.maxWidth == 720,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer constrains its card on wide desktop', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpComposer(tester);

    expect(find.byType(ResponsiveAppShell), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox && widget.constraints.maxWidth == 720,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
