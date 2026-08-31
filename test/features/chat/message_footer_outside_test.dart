import 'dart:io';

import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('the time renders below the message text, not beside it', (
    tester,
  ) async {
    // Measured rather than asserted on the flag: footerInsideBubble could
    // be false while some other layout still tucked the metadata into the
    // bubble's lower edge.
    final message = Message.fromRow({
      'id': 'm1',
      'client_message_id': 'c1',
      'relationship_id': 'r1',
      'sender_id': 'u1',
      'content': 'hello there',
      'created_at': DateTime(2026, 10, 12, 14, 30).toIso8601String(),
    }, currentUserId: 'u1');

    await tester.pumpWidget(
      ProviderScope(
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                currentUserId: 'u1',
                // The footer only renders for the latest of a run, which is
                // why this reads as "the last bubble" on screen.
                showLatestTimestamp: true,
              ),
            ),
          ),
        ),
      ),
    );

    final text = tester.getRect(find.text('hello there'));
    final time = tester.getRect(find.textContaining(':').first);

    expect(
      time.top,
      greaterThanOrEqualTo(text.bottom),
      reason:
          'the timestamp starts at ${time.top} but the text ends at '
          '${text.bottom} — the footer is still inside the bubble',
    );
  });

  test('no message type opts into an inside-the-bubble footer', () {
    final bubble =
        File(
          'lib/features/chat/presentation/widgets/message_bubble.dart',
        ).readAsStringSync();

    expect(bubble, contains('footerInsideBubble: false'));
  });

  testWidgets('the footer time is white; a read receipt turns primary', (
    tester,
  ) async {
    // The footer sits on the chat wallpaper now, not on a bubble, so the
    // on-bubble metadata colours (a green and a grey) no longer apply. The
    // read state keeps its own colour — that contrast IS the signal.
    Future<void> pumpWith(MessageStatus status) async {
      final message = Message.fromRow({
        'id': 'm1',
        'client_message_id': 'c1',
        'relationship_id': 'r1',
        'sender_id': 'u1',
        'content': 'hello there',
        'created_at': DateTime(2026, 10, 12, 14, 30).toIso8601String(),
      }, currentUserId: 'u1').copyWith(status: status);

      await tester.pumpWidget(
        ProviderScope(
          child: withScreenUtil(
            MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  key: ValueKey(status),
                  message: message,
                  currentUserId: 'u1',
                  showLatestTimestamp: true,
                  showStatus: true,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpWith(MessageStatus.delivered);
    final time = tester.widget<Text>(find.textContaining(':').first);
    expect(
      time.style?.color,
      Colors.white,
      reason: 'the time reads against the wallpaper, not a bubble',
    );

    final delivered = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(delivered.color, Colors.white);

    await pumpWith(MessageStatus.read);
    final read = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(
      read.color,
      isNot(Colors.white),
      reason: 'a read receipt is the one part that changes colour',
    );
  });
}
