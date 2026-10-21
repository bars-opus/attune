import 'package:shared_preferences/shared_preferences.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  late List<String> platformHaptics;
  late FakeHaptics fake;
  late List<String> reacted;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platformHaptics = [];
    fake = FakeHaptics();
    reacted = [];
  });

  Future<void> pumpBubble(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platformHaptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final message = Message(
      id: 'm1',
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'hold me',
      createdAt: DateTime(2026, 7, 1, 15, 4),
      status: MessageStatus.delivered,
      isMine: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [hapticsProvider.overrideWithValue(fake)],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                currentUserId: 'me',
                onReact: reacted.add,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.longPress(find.text('hold me'));
    await tester.pumpAndSettle();
  }

  testWidgets('menu open fires exactly one light impact', (tester) async {
    await pumpBubble(tester);
    await openMenu(tester);
    expect(platformHaptics, ['HapticFeedbackType.lightImpact']);
    expect(fake.lightCount, 0);
    expect(fake.selectionCount, 0);
  });

  testWidgets('quick reaction fires exactly one selection click', (
    tester,
  ) async {
    await pumpBubble(tester);
    await openMenu(tester);
    platformHaptics.clear();
    await tester.tap(find.byKey(const ValueKey('focused-reaction-0')));
    await tester.pumpAndSettle();
    expect(reacted, ['❤️']);
    expect(platformHaptics, ['HapticFeedbackType.selectionClick']);
    expect(fake.selectionCount, 0);
  });

  Future<void> openFullPicker(WidgetTester tester) async {
    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('focused-reaction-more')));
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPicker), findsOneWidget);
    // The picker loads its emoji data asynchronously (real I/O, so off the
    // fake clock): poll for the grid's first emoji instead of a fixed wait
    // a loaded machine can outrun.
    final firstEmoji = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Text),
    );
    for (var i = 0; i < 200 && firstEmoji.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(firstEmoji, findsWidgets, reason: 'the emoji data loaded');
    await tester.pumpAndSettle();
    platformHaptics.clear();
  }

  testWidgets('full-picker pick fires one selection and reacts', (
    tester,
  ) async {
    await pumpBubble(tester);
    await openFullPicker(tester);
    // Tap the first emoji in the grid.
    final emoji = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(Text),
    );
    await tester.tap(emoji.first);
    await tester.pumpAndSettle();
    expect(reacted, hasLength(1));
    expect(fake.selectionCount, 1);
    expect(fake.lightCount, 0);
    expect(platformHaptics, isEmpty);
  });

  testWidgets('dismissing the full picker fires no selection', (tester) async {
    await pumpBubble(tester);
    await openFullPicker(tester);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(reacted, isEmpty);
    expect(fake.selectionCount, 0);
    expect(platformHaptics, isEmpty);
  });

  testWidgets('a bubble with no ProviderScope logs why the pick is silent', (
    tester,
  ) async {
    // T10 carry: the haptics lookup's failure used to be swallowed by a
    // bare catch (_), indistinguishable from a working lookup.
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logged.add(message);
    };
    addTearDown(() => debugPrint = original);
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: Message(
                id: 'm1',
                clientMessageId: 'c1',
                relationshipId: 'r1',
                senderId: 'partner',
                content: 'hold me',
                createdAt: DateTime(2026, 7, 1, 15, 4),
                status: MessageStatus.delivered,
                isMine: false,
              ),
              currentUserId: 'me',
              onReact: reacted.add,
            ),
          ),
        ),
      ),
    );
    await openMenu(tester);
    debugPrint = original;
    expect(
      logged.where((line) => line.contains('reaction picker haptics')),
      hasLength(1),
    );
  });
}
