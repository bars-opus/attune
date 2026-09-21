import 'dart:convert';

import 'package:animated_emoji/animated_emoji.dart';
import 'package:attune/core/widgets/universal_bubble.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/emoji_message_content.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

Message message(String content, {bool mine = false}) => Message.fromRow({
  'id': 'm1',
  'client_message_id': 'c1',
  'relationship_id': 'r1',
  'sender_id': mine ? 'me' : 'partner',
  'content': content,
  'created_at': '2026-09-21T12:00:00Z',
}, currentUserId: 'me');

void main() {
  testWidgets(
    'scrolling an older emoji into view replays once per appearance',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 240,
              child: SingleChildScrollView(
                controller: scroll,
                child: const Column(
                  children: [
                    SizedBox(height: 400),
                    EmojiMessageContent(glyphs: ['😴'], animate: false),
                    SizedBox(height: 400),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Animation<double> playback() =>
          tester.widget<AnimatedEmoji>(find.byType(AnimatedEmoji)).controller!;
      expect(playback().value, 0);
    scroll.jumpTo(300);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
      expect(playback().value, greaterThan(0));
      await tester.pumpAndSettle();
      expect(playback().value, 1);
      scroll.jumpTo(310);
      await tester.pumpAndSettle();
      expect(
        playback().value,
        1,
        reason: 'small visible scrolls do not restart',
      );
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
    scroll.jumpTo(300);
    await tester.pump();
    await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(playback().value, greaterThan(0));
      expect(playback().value, lessThan(1));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('emoji waits until the send flight has revealed its row', (
    tester,
  ) async {
    Future<void> show(bool enabled) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmojiMessageContent(
            glyphs: const ['😴'],
            animate: true,
            playbackEnabled: enabled,
          ),
        ),
      ),
    );
    await show(false);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedEmoji>(find.byType(AnimatedEmoji))
          .controller!
          .value,
      0,
    );
    await show(true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester
          .widget<AnimatedEmoji>(find.byType(AnimatedEmoji))
          .controller!
          .value,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
  });
  testWidgets('keyboard sleeping emoji uses animated artwork on arrival', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmojiMessageContent(glyphs: ['😴'], animate: true),
        ),
      ),
    );
    expect(find.byType(AnimatedEmoji), findsOneWidget);
    await tester.pumpAndSettle();
    final emoji = tester.widget<AnimatedEmoji>(find.byType(AnimatedEmoji));
    expect(emoji.controller!.value, 1);
  });
  test('emoji detection preserves clusters and rejects ordinary text', () {
    for (final content in [
      '🙄',
      '❤️❤️',
      '👍🏿',
      '👨‍👩‍👧‍👦',
      '🇬🇭',
      '1️⃣',
      '❤️\n😊',
    ]) {
      expect(emojiMessageGlyphs(message(content)), isNotEmpty, reason: content);
    }
    for (final content in ['', '123', 'Hi ❤️', ':)', '❤️ hello', '!!!']) {
      expect(emojiMessageGlyphs(message(content)), isEmpty, reason: content);
    }
    expect(
      emojiMessageGlyphs(message('❤️').copyWith(mediaType: 'image')),
      isEmpty,
    );
    expect(
      emojiMessageGlyphs(message('❤️').copyWith(deletedAt: DateTime.now())),
      isEmpty,
    );
  });

  testWidgets('every supported animation is bundled as valid Lottie JSON', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final emoji in bundledMessageEmojis) {
        final data =
            jsonDecode(
                  await rootBundle.loadString(
                    'packages/animated_emoji/lottie/${emoji.name}.json',
                  ),
                )
                as Map<String, dynamic>;
        expect(data['layers'], isNotEmpty, reason: emoji.name);
      }
    });
  });

  for (final mine in [false, true]) {
    testWidgets('emoji-only message is enlarged and bare (mine=$mine)', (
      tester,
    ) async {
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message('🙄', mine: mine)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bubble = tester.widget<UniversalBubble>(
        find.byType(UniversalBubble),
      );
      expect(bubble.bubbleColor, Colors.transparent);
      expect(bubble.showShadow, isFalse);
      final emoji = tester.widget<AnimatedEmoji>(find.byType(AnimatedEmoji));
      expect(emoji.size, 68);
      expect(emoji.source, AnimatedEmojiSource.asset);
      expect(emoji.controller!.value, 0, reason: 'history must remain static');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('text with an emoji keeps its ordinary bubble', (tester) async {
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(body: MessageBubble(message: message('Hello ❤️'))),
        ),
      ),
    );
    expect(find.byType(EmojiMessageContent), findsNothing);
    final bubble = tester.widget<UniversalBubble>(find.byType(UniversalBubble));
    expect(bubble.bubbleColor, isNot(Colors.transparent));
    expect(bubble.showShadow, isTrue);
  });

  testWidgets('unsupported animated skin tone keeps its exact native emoji', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmojiMessageContent(glyphs: ['👍🏿'], animate: true),
        ),
      ),
    );
    expect(find.text('👍🏿'), findsOneWidget);
    expect(find.byType(AnimatedEmoji), findsNothing);
  });

  testWidgets(
    'new emoji animates once and stops, reduced motion stays static',
    (tester) async {
      Future<void> show(bool reduced) => tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Scaffold(
              body: EmojiMessageContent(glyphs: ['❤️'], animate: true),
            ),
          ),
        ),
      );
      await show(false);
      await tester.pumpAndSettle();
      var emoji = tester.widget<AnimatedEmoji>(find.byType(AnimatedEmoji));
      expect(emoji.controller!.value, 1);
      await show(false);
      expect(
        tester
            .widget<AnimatedEmoji>(find.byType(AnimatedEmoji))
            .controller!
            .value,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await show(true);
      await tester.pumpAndSettle();
      emoji = tester.widget<AnimatedEmoji>(find.byType(AnimatedEmoji));
      expect(emoji.controller!.value, 0);
    },
  );

  testWidgets('many emoji wrap within a narrow viewport', (tester) async {
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: MessageBubble(message: message('❤️' * 20)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
