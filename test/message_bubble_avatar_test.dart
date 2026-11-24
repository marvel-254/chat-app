import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/chat/widgets.dart';

void main() {
  group('bubble avatar visibility', () {
    bool visible({
      bool mine = false,
      bool groupedNext = false,
      String? peerId = 'peer-1',
      String senderId = 'peer-1',
    }) =>
        showMessageBubbleAvatar(
          mine: mine,
          groupedNext: groupedNext,
          peerId: peerId,
          senderId: senderId,
        );

    test('last inbound bubble from the peer shows an avatar', () {
      expect(visible(), isTrue);
    });

    test('grouped, own and unknown-sender bubbles do not', () {
      expect(visible(groupedNext: true), isFalse);
      expect(visible(mine: true), isFalse);
      expect(visible(peerId: null), isFalse);
      expect(visible(senderId: 'someone-else'), isFalse);
    });
  });

  group('MessageBubbleAvatar', () {
    testWidgets('renders a photo when a peer URL is available', (tester) async {
      const url = 'https://example.invalid/peer.png';
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MessageBubbleAvatar(name: 'A', url: url),
        ),
      ));

      expect(
        find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == url),
        findsOneWidget,
      );
    });

    testWidgets('falls back to initials without a URL', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MessageBubbleAvatar(name: 'A')),
      ));

      expect(find.text('A'), findsOneWidget);
    });
  });
}
