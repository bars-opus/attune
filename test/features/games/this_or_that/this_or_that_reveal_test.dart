import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/platform/feel/game_burst.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/reveal_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../platform/support/game_test_support.dart';
import 'support/this_or_that_fakes.dart';

/// This or That's waiting screen and reveal, in the games' tiles.
void main() {
  setUpAll(loadGameTestFonts);

  const longOption = 'Stay in and cook something slow together';
  const youTile = ValueKey('this-or-that-reveal-you');
  const partnerTile = ValueKey('this-or-that-reveal-partner');
  const youFlip = ValueKey('this-or-that-reveal-you-flip');
  const partnerFlip = ValueKey('this-or-that-reveal-partner-flip');
  const lockedTile = ValueKey('this-or-that-locked-pick');

  RevealScreen reveal({
    Key? key,
    String you = 'a',
    String partner = 'a',
    String optionA = 'Stay in',
    String optionB = 'Go out',
    String partnerName = 'Ama',
    bool celebrate = true,
    bool hasPrevious = false,
    VoidCallback? onPrevious,
    FutureOr<void> Function()? onNext,
  }) {
    String text(String side) => side == 'a' ? optionA : optionB;
    String emoji(String side) => side == 'a' ? '🛋️' : '✨';
    return RevealScreen(
      key: key,
      questionText: 'Friday night: stay in or go out?',
      userChoice: you,
      userChoiceText: text(you),
      userChoiceEmoji: emoji(you),
      partnerChoice: partner,
      partnerChoiceText: text(partner),
      partnerChoiceEmoji: emoji(partner),
      partnerName: partnerName,
      roundNumber: 3,
      totalRounds: 10,
      isMatch: you == partner,
      celebrate: celebrate,
      hasPrevious: hasPrevious,
      onPrevious: onPrevious,
      onNext: onNext ?? () {},
    );
  }

  WaitingScreen waiting({
    String partnerName = 'Ama',
    String optionA = 'Stay in',
    String optionB = 'Go out',
    DateTime? answeredAt,
  }) => WaitingScreen(
    sessionId: 'session-1',
    roundId: 'round-3',
    questionText: 'Friday night: stay in or go out?',
    userChoice: 'a',
    userChoiceText: optionA,
    userChoiceEmoji: '🛋️',
    optionA: optionA,
    optionB: optionB,
    emojiA: '🛋️',
    emojiB: '✨',
    roundNumber: 3,
    totalRounds: 10,
    isPartnerA: true,
    partnerName: partnerName,
    answeredAt: answeredAt,
  );

  List<Override> waitingOverrides() => [
    thisOrThatRepositoryProvider.overrideWithValue(MockThisOrThatRepository()),
    currentUserIdProvider.overrideWithValue('user-a'),
  ];

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = phone,
    bool reduceMotion = false,
    FakeSoundService? sounds,
    FakeHaptics? haptics,
    List<Override> overrides = const [],
  }) async {
    useSurface(tester, size);
    await tester.pumpWidget(
      gameHost(
        screen,
        prefs: await testPrefs(),
        sound: sounds,
        haptics: haptics,
        reduceMotion: reduceMotion,
        overrides: overrides,
      ),
    );
  }

  GameBurst burst(WidgetTester tester) {
    final found = find.byType(GameBurst);
    expect(found, findsOneWidget);
    return tester.widget<GameBurst>(found);
  }

  /// How far through its run the burst's painter is drawing.
  double burstProgress(WidgetTester tester) {
    final paints = find.descendant(
      of: find.byType(GameBurst),
      matching: find.byType(CustomPaint),
    );
    expect(paints, findsWidgets);
    for (final element in paints.evaluate()) {
      final painter = (element.widget as CustomPaint).painter;
      if (painter is GameBurstPainter) return painter.progress;
    }
    fail('the burst draws nothing');
  }

  Color faceOf(WidgetTester tester, Key key) =>
      tester.widget<GameTile>(find.byKey(key)).color;

  /// Every word drawn on the tile under [key], and how well it reads
  /// against the face it is drawn on: the nearest painted box above it,
  /// read from what is built.
  List<({String text, double contrast})> inkOnTile(
    WidgetTester tester,
    Key key,
  ) {
    final found = <({String text, double contrast})>[];
    final texts = find.descendant(
      of: find.byKey(key),
      matching: find.byType(RichText),
    );
    for (final element in texts.evaluate()) {
      final rich = element.widget as RichText;
      final text = rich.text.toPlainText();
      if (text.trim().isEmpty) continue;
      Color? surface;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color != null) {
          surface = (widget.decoration as BoxDecoration).color;
          return false;
        }
        return true;
      });
      expect(surface, isNotNull, reason: '"$text" is drawn on nothing');
      final ink = rich.text.style!.color!;
      found.add((
        text: text,
        contrast: contrast(Color.alphaBlend(ink, surface!), surface!),
      ));
    }
    return found;
  }

  /// Nothing on screen ran out of lines or past the screen's edges.
  void expectNothingClipped(WidgetTester tester, Size size) {
    final paragraphs = find.descendant(
      of: find.byType(MaterialApp),
      matching: find.byType(RichText),
    );
    expect(paragraphs, findsWidgets);
    for (final element in paragraphs.evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      final text = paragraph.text.toPlainText();
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text" clipped');
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(rect.left, greaterThanOrEqualTo(0), reason: text);
      expect(rect.right, lessThanOrEqualTo(size.width), reason: text);
    }
  }

  group('the reveal', () {
    testWidgets('a match bursts once and plays the match sound once', (
      tester,
    ) async {
      final sounds = FakeSoundService();
      final haptics = FakeHaptics();
      final rebuild = ValueNotifier(0);
      addTearDown(rebuild.dispose);
      await pump(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (context, value, child) => reveal(),
        ),
        sounds: sounds,
        haptics: haptics,
      );

      // The burst runs: somewhere on the way its painter is mid-flight.
      var highest = 0.0;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        final progress = burstProgress(tester);
        if (progress > highest) highest = progress;
      }
      expect(highest, greaterThan(0));
      await tester.pumpAndSettle();

      expect(sounds.played, [AppSound.gameMatch]);
      expect(haptics.mediumCount, 1);
      expect(burst(tester).count, 1);

      rebuild.value++;
      await tester.pumpAndSettle();
      expect(sounds.played, [AppSound.gameMatch]);
      expect(haptics.mediumCount, 1);
      expect(burst(tester).count, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('different answers reveal without a burst', (tester) async {
      // Control: the test above, where the same screen on a match bursts.
      final sounds = FakeSoundService();
      final haptics = FakeHaptics();
      await pump(
        tester,
        reveal(partner: 'b'),
        sounds: sounds,
        haptics: haptics,
      );
      await tester.pumpAndSettle();

      expect(sounds.played, [AppSound.gameReveal]);
      expect(haptics.lightCount, 1);
      expect(haptics.mediumCount, 0);
      expect(burst(tester).count, 0);
    });

    testWidgets('a round looked back on plays nothing at all', (tester) async {
      // Control: the two tests above, where a live reveal plays once.
      final sounds = FakeSoundService();
      final haptics = FakeHaptics();
      await pump(
        tester,
        reveal(celebrate: false),
        sounds: sounds,
        haptics: haptics,
      );
      await tester.pumpAndSettle();

      expect(find.text('Same wavelength'), findsOneWidget);
      expect(sounds.played, isEmpty);
      expect(haptics.mediumCount + haptics.lightCount, 0);
      expect(burst(tester).count, 0);
    });

    testWidgets('under reduce motion both picks are there on the first '
        'frame', (tester) async {
      final sounds = FakeSoundService();
      await pump(
        tester,
        reveal(partner: 'b'),
        reduceMotion: true,
        sounds: sounds,
      );

      expect(find.text('Stay in'), findsOneWidget);
      expect(find.text('Go out'), findsOneWidget);
      for (final flip in [youFlip, partnerFlip]) {
        expect(
          tester.widget<Transform>(find.byKey(flip)).transform.isIdentity(),
          isTrue,
          reason: '$flip is not at rest',
        );
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(sounds.played, [AppSound.gameReveal]);
    });

    testWidgets('with motion, the picks turn over one after the other', (
      tester,
    ) async {
      // The control for the test above: with motion, the first frame has
      // neither pick at rest yet.
      await pump(tester, reveal(partner: 'b'));

      bool atRest(Key flip) =>
          tester.widget<Transform>(find.byKey(flip)).transform.isIdentity();
      expect(atRest(youFlip), isFalse);
      expect(atRest(partnerFlip), isFalse);

      var youFirst = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (atRest(youFlip) && !atRest(partnerFlip)) youFirst = true;
      }
      expect(youFirst, isTrue, reason: 'the two picks landed together');
      await tester.pumpAndSettle();
      expect(atRest(youFlip), isTrue);
      expect(atRest(partnerFlip), isTrue);
    });

    testWidgets('each pick is drawn in its own option\'s colour', (
      tester,
    ) async {
      await pump(tester, reveal(partner: 'b'), reduceMotion: true);
      final palette = ThisOrThatPalette.of(
        tester.element(find.byType(RevealScreen)),
      );

      expect(faceOf(tester, youTile), palette.thisColor);
      expect(faceOf(tester, partnerTile), palette.thatColor);

      // On a match, both are the same colour.
      await pump(
        tester,
        reveal(key: const ValueKey('match'), you: 'b', partner: 'b'),
        reduceMotion: true,
      );
      expect(faceOf(tester, youTile), palette.thatColor);
      expect(faceOf(tester, partnerTile), palette.thatColor);
    });

    testWidgets('"You" and the partner\'s name sit above their picks', (
      tester,
    ) async {
      await pump(tester, reveal(partner: 'b'), reduceMotion: true);

      for (final (label, tile) in [('YOU', youTile), ('AMA', partnerTile)]) {
        final caption = tester.getRect(find.text(label));
        final face = tester.getRect(find.byKey(tile));
        expect(caption.bottom, lessThanOrEqualTo(face.top), reason: label);
        expect(caption.center.dx, closeTo(face.center.dx, face.width / 2));
      }
    });

    testWidgets('every word on both picks reads on its own face', (
      tester,
    ) async {
      for (final partner in ['a', 'b']) {
        await pump(
          tester,
          reveal(key: ValueKey(partner), partner: partner),
          reduceMotion: true,
        );
        final ink = [
          ...inkOnTile(tester, youTile),
          ...inkOnTile(tester, partnerTile),
        ];
        expect(ink.map((piece) => piece.text), containsAll(['Stay in']));
        expect(ink.length, greaterThanOrEqualTo(4));
        expect(
          ink
              .where((piece) => piece.contrast < 4.5)
              .map((p) => '${p.text} (${p.contrast.toStringAsFixed(2)})'),
          isEmpty,
        );
      }
    });

    testWidgets('next is the shell\'s pill and stays busy while advancing; '
        'previous is the quieter pill', (tester) async {
      final advance = Completer<void>();
      var nexts = 0;
      var previous = 0;
      await pump(
        tester,
        reveal(
          hasPrevious: true,
          onPrevious: () => previous++,
          onNext: () {
            nexts++;
            return advance.future;
          },
        ),
        reduceMotion: true,
      );

      final next = find.widgetWithText(GamePrimaryButton, 'Next round');
      expect(next, findsOneWidget);
      expect(tester.widget<GamePrimaryButton>(next).busy, isFalse);
      await tester.tap(find.byType(GameSecondaryButton));
      expect(previous, 1);

      await tester.tap(next);
      await tester.pump();
      expect(nexts, 1);
      expect(tester.widget<GamePrimaryButton>(next).busy, isTrue);

      advance.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<GamePrimaryButton>(next).busy, isFalse);
    });

    testWidgets('on the smallest phone, long picks and a long name fit', (
      tester,
    ) async {
      const small = Size(320, 568);
      for (final partner in ['a', 'b']) {
        await pump(
          tester,
          reveal(
            key: ValueKey(partner),
            partner: partner,
            optionA: longOption,
            optionB: longOption,
            partnerName: 'Kwame Mensah',
            hasPrevious: true,
            onPrevious: () {},
          ),
          size: small,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(longOption), findsNWidgets(2));
        expect(find.text('KWAME MENSAH'), findsOneWidget);
        expectNothingClipped(tester, small);
      }
    });
  });

  group('waiting', () {
    testWidgets('the waiting line names the partner', (tester) async {
      await pump(
        tester,
        waiting(),
        reduceMotion: true,
        overrides: waitingOverrides(),
      );

      expect(
        find.text(
          'Your answer is tucked away. The reveal begins as soon as Ama '
          'locks theirs in.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('with no name known, the line says "your partner"', (
      tester,
    ) async {
      // Control: the test above, where the name is known.
      await pump(
        tester,
        waiting(partnerName: 'Partner'),
        reduceMotion: true,
        overrides: waitingOverrides(),
      );

      expect(
        find.text(
          'Your answer is tucked away. The reveal begins as soon as your '
          'partner locks theirs in.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('both of you'), findsNothing);
    });

    testWidgets('the locked pick is one tile in the pick\'s colour, and '
        'follows a changed pick', (tester) async {
      final repository = MockThisOrThatRepository();
      when(
        () => repository.submitAnswer(
          roundId: any(named: 'roundId'),
          userId: any(named: 'userId'),
          choice: any(named: 'choice'),
          isPartnerA: any(named: 'isPartnerA'),
        ),
      ).thenAnswer((_) async {});
      await pump(
        tester,
        waiting(),
        reduceMotion: true,
        overrides: [
          thisOrThatRepositoryProvider.overrideWithValue(repository),
          currentUserIdProvider.overrideWithValue('user-a'),
        ],
      );
      final palette = ThisOrThatPalette.of(
        tester.element(find.byType(WaitingScreen)),
      );

      final tile = find.byKey(lockedTile);
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('YOUR LOCKED PICK')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('🛋️ Stay in')),
        findsOneWidget,
      );
      expect(faceOf(tester, lockedTile), palette.thisColor);

      await tester.tap(
        find.widgetWithText(GameSecondaryButton, 'Change my pick'),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Go out'));
      await tester.tap(find.text('Go out'));
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(of: tile, matching: find.text('✨ Go out')),
        findsOneWidget,
      );
      expect(faceOf(tester, lockedTile), palette.thatColor);
    });

    testWidgets('every word on the locked pick reads on its face', (
      tester,
    ) async {
      await pump(
        tester,
        waiting(),
        reduceMotion: true,
        overrides: waitingOverrides(),
      );

      final ink = inkOnTile(tester, lockedTile);
      expect(ink.map((piece) => piece.text), contains('🛋️ Stay in'));
      expect(ink.length, greaterThanOrEqualTo(3));
      expect(
        ink
            .where((piece) => piece.contrast < 4.5)
            .map((p) => '${p.text} (${p.contrast.toStringAsFixed(2)})'),
        isEmpty,
      );
    });

    testWidgets('nudge and change are the shell\'s quieter pills', (
      tester,
    ) async {
      await pump(
        tester,
        waiting(answeredAt: DateTime.now().subtract(const Duration(hours: 3))),
        reduceMotion: true,
        overrides: waitingOverrides(),
      );

      expect(
        find.widgetWithText(GameSecondaryButton, 'Nudge Ama'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(GameSecondaryButton, 'Change my pick'),
        findsOneWidget,
      );
    });

    testWidgets('on the smallest phone, a long pick and a long name fit', (
      tester,
    ) async {
      const small = Size(320, 568);
      await pump(
        tester,
        waiting(
          partnerName: 'Kwame Mensah',
          optionA: longOption,
          optionB: longOption,
          answeredAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
        size: small,
        reduceMotion: true,
        overrides: waitingOverrides(),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('🛋️ $longOption'), findsOneWidget);
      expect(find.text('Nudge Kwame Mensah'), findsOneWidget);
      expectNothingClipped(tester, small);
    });
  });
}
