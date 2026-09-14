import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/message_info_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/chat_test_harness.dart';

Message _message({
  bool isMine = true,
  DateTime? createdAt,
  DateTime? deliveredAt,
  DateTime? readAt,
  DateTime? editedAt,
  DateTime? viewedAt,
  DateTime? deletedAt,
  MessageStatus status = MessageStatus.sent,
}) => Message(
  id: 'm1',
  clientMessageId: 'c1',
  relationshipId: 'r1',
  senderId: isMine ? 'me' : 'them',
  content: 'hello',
  createdAt: createdAt ?? DateTime(2026, 11, 8, 14, 0),
  status: status,
  isMine: isMine,
  deliveredAt: deliveredAt,
  readAt: readAt,
  editedAt: editedAt,
  viewedAt: viewedAt,
  deletedAt: deletedAt,
);

Widget _wrap(Message message) => withScreenUtil(
  MaterialApp(home: MessageInfoScreen(message: message)),
);

void main() {
  testWidgets('shows the message preview and the sent time', (tester) async {
    final message = _message();
    await tester.pumpWidget(_wrap(message));

    expect(find.byType(MessageBubble), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(
      find.textContaining(MyDateFormat.toWeekdayMonth(message.createdAt)),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows Delivered and Read for a sent message that has both',
    (tester) async {
      final message = _message(
        deliveredAt: DateTime(2026, 11, 8, 14, 1),
        readAt: DateTime(2026, 11, 8, 14, 5),
      );
      await tester.pumpWidget(_wrap(message));

      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);
    },
  );

  testWidgets(
    'omits Delivered and Read entirely when neither has happened yet — '
    'no placeholder row for something that has not happened',
    (tester) async {
      await tester.pumpWidget(_wrap(_message()));

      expect(find.text('Delivered'), findsNothing);
      expect(find.text('Read'), findsNothing);
    },
  );

  testWidgets(
    'never shows Delivered/Read for a message that is not mine — those '
    'only mean something for a message the viewer sent',
    (tester) async {
      final message = _message(
        isMine: false,
        deliveredAt: DateTime(2026, 11, 8, 14, 1),
        readAt: DateTime(2026, 11, 8, 14, 5),
      );
      await tester.pumpWidget(_wrap(message));

      expect(find.text('Delivered'), findsNothing);
      expect(find.text('Read'), findsNothing);
    },
  );

  testWidgets('shows Edited when the message was edited', (tester) async {
    final message = _message(editedAt: DateTime(2026, 11, 8, 15, 0));
    await tester.pumpWidget(_wrap(message));

    expect(find.text('Edited'), findsOneWidget);
  });

  testWidgets(
    'shows Viewed for a view-once message the recipient opened, distinct '
    'from an ordinary read receipt',
    (tester) async {
      final message = _message(
        isMine: true,
        viewedAt: DateTime(2026, 11, 8, 16, 0),
      );
      await tester.pumpWidget(_wrap(message));

      expect(find.text('Viewed'), findsOneWidget);
    },
  );

  testWidgets(
    'a deleted message shows only the tombstone — nothing else meaningful '
    'can follow a deletion',
    (tester) async {
      final message = _message(
        deletedAt: DateTime(2026, 11, 8, 17, 0),
        deliveredAt: DateTime(2026, 11, 8, 14, 1),
        readAt: DateTime(2026, 11, 8, 14, 5),
      );
      await tester.pumpWidget(_wrap(message));

      // Twice, deliberately: MessageBubble's own tombstone renders it in
      // the preview, and this screen's info row repeats it below —
      // findsAtLeastNWidgets rather than pinning the exact count, since
      // that count is MessageBubble's implementation detail, not this
      // screen's contract.
      expect(
        find.text('You deleted this message'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Delivered'), findsNothing);
      expect(find.text('Read'), findsNothing);
      expect(find.text('Sent'), findsNothing);
    },
  );

  testWidgets('the back button pops the screen', (tester) async {
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => MessageInfoScreen(message: _message()),
                        ),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageInfoScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(MessageInfoScreen), findsNothing);
  });
}
