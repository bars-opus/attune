import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/live_message_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Message message({
  String content = 'Hello',
  Map<String, Set<String>> reactions = const {},
}) => Message.fromRow({
  'id': 'm1',
  'client_message_id': 'c1',
  'relationship_id': 'r1',
  'sender_id': 'partner',
  'content': content,
  'created_at': '2026-09-20T12:00:00Z',
}, currentUserId: 'me').copyWith(reactions: reactions);

void main() {
  Future<void> show(
    WidgetTester tester,
    Message value, {
    bool arrival = false,
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: LiveMessageMotion(
              message: value,
              viewerId: 'me',
              animateArrival: arrival,
              child: const SizedBox(
                width: 150,
                height: 50,
                child: Text('bubble'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final sparkles = find.byKey(const ValueKey('live-message-sparkles'));

  test('only short supported emoji-only user messages qualify', () {
    expect(isAnimatedEmojiMessage(message(content: '❤️ 😂')), isTrue);
    expect(isAnimatedEmojiMessage(message(content: 'hello ❤️')), isFalse);
    expect(isAnimatedEmojiMessage(message(content: '❤️❤️❤️❤️')), isFalse);
    expect(isAnimatedEmojiMessage(message(content: '')), isFalse);
    expect(
      isAnimatedEmojiMessage(
        message(content: '🎉').copyWith(mediaType: 'image'),
      ),
      isFalse,
    );
    expect(
      isAnimatedEmojiMessage(
        message(content: '🎉').copyWith(deletedAt: DateTime.now()),
      ),
      isFalse,
    );
  });

  testWidgets(
    'history stays still, partner additions play once without changing layout',
    (tester) async {
      final baseline = message(
        reactions: {
          '❤️': {'partner'},
        },
      );
      await show(tester, baseline);
      expect(sparkles, findsNothing);
      final size = tester.getSize(find.byType(LiveMessageMotion));
      final changed = message(
        reactions: {
          '❤️': {'partner'},
          '😂': {'partner'},
        },
      );
      await show(tester, changed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sparkles, findsOneWidget);
      expect(tester.getSize(find.byType(LiveMessageMotion)), size);
      await tester.pumpAndSettle();
      expect(sparkles, findsNothing);
      await show(tester, changed.copyWith(id: 'server-id'));
      expect(sparkles, findsNothing);
      await show(tester, baseline);
      expect(sparkles, findsNothing);
    },
  );

  testWidgets(
    'own reactions and their server echoes do not replay the flight landing',
    (tester) async {
      await show(tester, message());
      final reacted = message(
        reactions: {
          '❤️': {'me'},
        },
      );
      await show(tester, reacted);
      expect(sparkles, findsNothing);
      await show(tester, reacted.copyWith(id: 'canonical'));
      expect(sparkles, findsNothing);
    },
  );

  testWidgets('new emoji arrivals animate once, ordinary messages do not', (
    tester,
  ) async {
    await show(tester, message(content: '🎉'), arrival: true);
    expect(sparkles, findsOneWidget);
    await tester.pumpAndSettle();
    await show(tester, message(content: '🎉'), arrival: true);
    expect(sparkles, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await show(tester, message(), arrival: true);
    expect(sparkles, findsNothing);
  });

  testWidgets('reduced motion suppresses arrivals and live reactions', (
    tester,
  ) async {
    await show(
      tester,
      message(content: '❤️'),
      arrival: true,
      reduceMotion: true,
    );
    expect(sparkles, findsNothing);
    await show(
      tester,
      message(
        reactions: {
          '❤️': {'partner'},
        },
      ),
      reduceMotion: true,
    );
    expect(sparkles, findsNothing);
  });

  testWidgets('disposing mid-effect leaves no animation behind', (
    tester,
  ) async {
    await show(tester, message(content: '😂'), arrival: true);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
