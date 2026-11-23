import 'dart:async';

import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_registry.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/games_catalogue.dart';
import 'package:attune/features/games/platform/legacy/legacy_game_opener.dart';
import 'package:attune/features/games/platform/shell/game_hub_card.dart';
import 'package:attune/features/games/platform/shell/games_hub_screen.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/demo_game.dart';
import 'support/game_test_support.dart';
import 'support/ink_on_ground.dart';
import 'support/route_recorder.dart';

const List<String> _launchTitles = [
  'This or That',
  'Truth or Dare',
  '36 Questions',
  'Word Hunt',
  'Snakes and Ladders',
];

Map<String, dynamic> _row(String id, String gameType) => {
  'id': id,
  'game_type': gameType,
  'initiator_id': 'me',
};

GameCardState _card({
  required String status,
  String? turn,
  bool? viewerAnswered,
  bool? partnerAnswered,
}) {
  return GameCardState(
    gameType: 'truth_or_dare',
    status: status,
    currentTurnUserId: turn,
    winnerUserId: null,
    currentRound: null,
    totalRounds: null,
    viewerAnswered: viewerAnswered,
    partnerAnswered: partnerAnswered,
  );
}

/// The session list a widget outside the hub sees.
class _OutsideReader extends ConsumerWidget {
  const _OutsideReader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(activeGamesProvider).valueOrNull;
    return Text(
      'outside:${rows?.length ?? '-'}',
      textDirection: TextDirection.ltr,
    );
  }
}

/// A redrawn game's controller: records the sessions it is asked to open.
class _RecordingController extends GameController {
  final List<String> openedSessions = [];

  @override
  GameLandingState watchLanding(WidgetRef ref) =>
      const GameLandingState(status: GameLandingStatus.fresh);

  @override
  Future<void> onPrimary(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) async {}

  @override
  Future<void> openSession(
    BuildContext context,
    WidgetRef ref, {
    required String sessionId,
  }) async {
    openedSessions.add(sessionId);
  }
}

void main() {
  // Real letters: whether two cards fit side by side is measured from the
  // names, and the test font's square glyphs are far wider than Roboto's.
  setUpAll(loadGameTestFonts);

  late List<Map<String, dynamic>> activeRows;
  late bool listFails;
  late int listReads;
  late Map<String, GameCardState?> cards;
  late Map<String, Stream<GameCardState?>> cardStreams;
  late List<(String, String?)> opened;
  late StreamController<void> events;

  setUp(() {
    activeRows = [];
    listFails = false;
    listReads = 0;
    cards = {};
    cardStreams = {};
    opened = [];
  });

  Future<void> pumpHub(
    WidgetTester tester, {
    Widget home = const GamesHubScreen(),
    Size surface = phone,
    double textScale = 1,
    bool recordOpens = true,
    String? partnerName = 'Ama',
    List<Override> overrides = const [],
    ThemeData? theme,
  }) async {
    useSurface(tester, surface);
    events = StreamController<void>();
    // Not awaited: after a failure the hub may still be listening, and
    // waiting on close would hang the file instead of reporting it.
    addTearDown(() => unawaited(events.close()));
    await tester.pumpWidget(
      gameRouterHost(
        home: home,
        prefs: await testPrefs(),
        textScale: textScale,
        theme: theme,
        overrides: [
          activeGamesProvider.overrideWith((ref) async {
            listReads++;
            if (listFails) throw Exception('offline');
            return List.of(activeRows);
          }),
          gameCardProvider.overrideWith(
            (ref, id) => cardStreams[id] ?? Stream.value(cards[id]),
          ),
          gameSessionEventsProvider.overrideWith((ref) => events.stream),
          currentUserIdProvider.overrideWithValue('me'),
          gamePartnerNameProvider.overrideWith((ref) async => partnerName),
          if (recordOpens)
            legacyGameOpenerProvider.overrideWithValue((
              context,
              gameType, {
              sessionId,
            }) async {
              opened.add((gameType, sessionId));
            }),
          ...overrides,
        ],
      ),
    );
    // The list, then each session's card.
    await tester.pump();
    await tester.pump();
  }

  /// Lets a push or pop finish.
  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// A card's change, then the frame that draws it.
  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// A pop, then the list read again, then the frame that draws it.
  Future<void> settleBack(WidgetTester tester) async {
    await settleRoute(tester);
    await tester.pump();
  }

  Finder sessionRow(String sessionId) =>
      find.byKey(ValueKey('games-hub-session-$sessionId'));

  for (final MapEntry(key: themeName, value: theme) in fitThemes.entries) {
    testWidgets('lists the five launch games under Play together'
        '${fitThemeSuffix(themeName, theme)}', (tester) async {
      await pumpHub(tester, theme: theme);

      final heading = tester.getRect(find.text('Play together'));
      for (final title in _launchTitles) {
        expect(find.text(title), findsOneWidget, reason: title);
        expect(
          tester.getRect(find.text(title)).top,
          greaterThan(heading.top),
          reason: '$title is under Play together',
        );
      }

      // This or That's card is the featured one: above the others, and wider.
      Finder cardOf(String title) =>
          find.ancestor(of: find.text(title), matching: find.byType(GameHubCard));
      final featured = tester.getRect(cardOf('This or That'));
      expect(tester.widget<GameHubCard>(cardOf('This or That')).featured, isTrue);
      final others = _launchTitles.skip(1).toList();
      expect(others, isNotEmpty);
      for (final title in others) {
        final rect = tester.getRect(cardOf(title));
        expect(tester.widget<GameHubCard>(cardOf(title)).featured, isFalse);
        expect(rect.top, greaterThan(featured.bottom), reason: title);
        expect(featured.width, greaterThan(rect.width), reason: title);
        expect(featured.height, greaterThan(rect.height), reason: title);
      }
      expect(find.text('Quick choices, shared reveals'), findsOneWidget);

      // Two to a row at the usual text size.
      expect(
        tester.getRect(cardOf('Truth or Dare')).top,
        tester.getRect(cardOf('36 Questions')).top,
      );
      expect(
        tester.getRect(cardOf('Truth or Dare')).height,
        tester.getRect(cardOf('36 Questions')).height,
      );
    });
  }

  testWidgets('a launch game opens its landing page', (tester) async {
    // Stands in for the sheet's "a built game still selects".
    await pumpHub(tester);

    await tester.tap(find.text('Truth or Dare'));
    await settleRoute(tester);

    expect(find.text('opened:gameLanding:truth_or_dare'), findsOneWidget);
  });

  testWidgets('a coming-soon game is labelled and takes no taps', (
    tester,
  ) async {
    // Stands in for the sheet's "a coming-soon row is inert and labelled".
    // Mirror has a controller (a session of it still opens from In play):
    // coming soon comes from its availability, not from that.
    final handle = tester.ensureSemantics();
    await pumpHub(tester);

    await tester.scrollUntilVisible(
      find.text('Mirror'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mirror'), warnIfMissed: false);
    await settleRoute(tester);

    // The control is "a launch game opens its landing page", where the same
    // tap navigates.
    expect(find.textContaining('opened:'), findsNothing);
    expect(find.byType(GamesHubScreen), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Mirror, coming soon')),
      matchesSemantics(label: 'Mirror, coming soon'),
    );
    handle.dispose();
  });

  testWidgets('a game in progress is listed and opens that session', (
    tester,
  ) async {
    // Stands in for the sheet's "an active game is listed and resumes on
    // tap".
    activeRows = [_row('s1', 'truth_or_dare')];
    cards['s1'] = _card(status: 'active', turn: 'me');
    await pumpHub(tester);

    expect(find.text('In play'), findsOneWidget);
    expect(
      find.descendant(
        of: sessionRow('s1'),
        matching: find.text('Truth or Dare'),
      ),
      findsOneWidget,
    );
    await tester.tap(sessionRow('s1'));
    await tester.pump();

    expect(opened, [('truth_or_dare', 's1')]);
  });

  testWidgets('a coming-soon game already in progress still opens', (
    tester,
  ) async {
    activeRows = [_row('s2', 'mirror')];
    cards['s2'] = _card(status: 'active', turn: 'me');
    await pumpHub(tester);

    expect(
      find.descendant(of: sessionRow('s2'), matching: find.text('Mirror')),
      findsOneWidget,
    );
    await tester.tap(sessionRow('s2'));
    await tester.pump();

    expect(opened, [('mirror', 's2')]);
  });

  testWidgets('names are words, never database values', (tester) async {
    // Stands in for the sheet's "every game_type that can reach
    // game_sessions resumes somewhere", and raw types never rendered. The
    // app's own opener: it quietly does nothing for a type it cannot route.
    activeRows = [_row('s3', 'brand_new_game')];
    await pumpHub(tester, recordOpens: false);

    expect(find.text('Brand New Game'), findsOneWidget);
    expect(find.text('brand_new_game'), findsNothing);

    await tester.tap(sessionRow('s3'));
    await settleRoute(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(GamesHubScreen), findsOneWidget);
  });

  testWidgets('a game in progress opens through its own controller', (
    tester,
  ) async {
    // A redrawn game opens its session itself; the chat's old routing is
    // only for games that have no controller.
    final controller = _RecordingController();
    activeRows = [_row('s1', 'demo')];
    cards['s1'] = _card(status: 'active', turn: 'me');
    await pumpHub(
      tester,
      overrides: [
        gameRegistryProvider.overrideWithValue(
          GameRegistry([demoGame(controller: controller), ...gameCatalogue]),
        ),
      ],
    );

    await tester.tap(sessionRow('s1'));
    await tester.pump();

    expect(controller.openedSessions, ['s1']);
    expect(opened, isEmpty);
  });

  testWidgets('a game this build does not know opens through the chat\'s '
      'routing', (tester) async {
    // The control for the test above: with no definition, the legacy
    // opener is asked, and it decides whether there is anywhere to go.
    activeRows = [_row('s3', 'brand_new_game')];
    await pumpHub(tester);

    await tester.tap(sessionRow('s3'));
    await tester.pump();

    expect(opened, [('brand_new_game', 's3')]);
  });

  testWidgets('says nothing under Games while the name is unknown', (
    tester,
  ) async {
    await pumpHub(tester, partnerName: null);
    // Only the section heading: no subtitle repeating it a few lines above.
    // The control is "says who to play with".
    expect(find.text('Play together'), findsOneWidget);
    expect(find.textContaining('Play with'), findsNothing);
  });

  testWidgets('nothing moves when the partner\'s name arrives', (tester) async {
    // The subtitle's line is held while the name is unknown, so the name
    // arriving does not push the games down under a finger.
    await pumpHub(tester, partnerName: null);
    expect(find.textContaining('Play with'), findsNothing);
    final unknown = tester.getTopLeft(find.text('Play together')).dy;

    await tester.pumpWidget(const SizedBox());
    await pumpHub(tester);
    // The control: the name is drawn this time.
    expect(find.text('Play with Ama'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Play together')).dy, unknown);
  });

  testWidgets('says who to play with', (tester) async {
    await pumpHub(tester);
    expect(find.text('Play with Ama'), findsOneWidget);
    expect(find.text('Play together'), findsOneWidget);
  });

  testWidgets('In play is not shown when nothing is in progress', (
    tester,
  ) async {
    // Stands in for the sheet's "neither section appears when both lists
    // are empty".
    await pumpHub(tester);
    expect(find.text('In play'), findsNothing);
    expect(find.text('Play together'), findsOneWidget);

    // The control: a game the partner starts arrives with its event.
    activeRows = [_row('s1', 'truth_or_dare')];
    events.add(null);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('In play'), findsOneWidget);
  });

  testWidgets('says whose turn it is, live', (tester) async {
    // Review Focus 2.
    final live = StreamController<GameCardState?>();
    addTearDown(() => unawaited(live.close()));
    activeRows = [_row('s1', 'truth_or_dare')];
    cardStreams['s1'] = live.stream;
    await pumpHub(tester);

    live.add(_card(status: 'active'));
    await pumpCard(tester);
    expect(find.text('Your turn'), findsOneWidget);

    live.add(
      _card(status: 'active', viewerAnswered: true, partnerAnswered: false),
    );
    await pumpCard(tester);
    expect(find.text('Waiting for Ama'), findsOneWidget);
    expect(find.text('Your turn'), findsNothing);
  });

  testWidgets('a game whose state is still loading shows no label', (
    tester,
  ) async {
    // landingAction would say "Play" for loading, on a game already under
    // way.
    final live = StreamController<GameCardState?>();
    addTearDown(() => unawaited(live.close()));
    activeRows = [_row('s1', 'truth_or_dare')];
    cardStreams['s1'] = live.stream;
    await pumpHub(tester);

    expect(sessionRow('s1'), findsOneWidget);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Your turn'), findsNothing);

    // The control: the label appears once the state does, and the row
    // opened while loading all along.
    await tester.tap(sessionRow('s1'));
    await tester.pump();
    expect(opened, [('truth_or_dare', 's1')]);
    live.add(_card(status: 'active', turn: 'me'));
    await pumpCard(tester);
    expect(
      find.descendant(of: sessionRow('s1'), matching: find.text('Your turn')),
      findsOneWidget,
    );
  });

  testWidgets('a failed session list still shows the games', (tester) async {
    listFails = true;
    await pumpHub(tester);

    expect(tester.takeException(), isNull);
    for (final title in _launchTitles) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // The control for its absence is "a game in progress is listed".
    expect(find.text('In play'), findsNothing);
  });

  for (final MapEntry(key: themeName, value: theme) in fitThemes.entries) {
    testWidgets('the largest text size scrolls and does not overflow'
        '${fitThemeSuffix(themeName, theme)}', (tester) async {
      // Stands in for the sheet's "the sheet grows with large text".
      activeRows = [_row('s1', 'truth_or_dare'), _row('s2', 'mirror')];
      cards['s1'] = _card(status: 'active', turn: 'me');
      cards['s2'] = _card(status: 'active', turn: 'partner');
      await pumpHub(tester, textScale: 2, theme: theme);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Never Have I Ever'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Never Have I Ever'), findsOneWidget);
    });
  }

  for (final MapEntry(key: themeName, value: theme) in fitThemes.entries) {
    testWidgets('at the largest text size cards go one to a row, so no name '
        'breaks mid-word${fitThemeSuffix(themeName, theme)}', (tester) async {
      Rect cardRect(String title) => tester.getRect(
        find.ancestor(of: find.text(title), matching: find.byType(GameHubCard)),
      );

      // The control, at the usual size two to a row, is in "lists the five
      // launch games under Play together".
      await pumpHub(tester, textScale: 2, theme: theme);
      final featured = cardRect('This or That');
      expect(cardRect('Truth or Dare').width, featured.width);
      expect(
        cardRect('36 Questions').top,
        greaterThan(cardRect('Truth or Dare').bottom),
      );
      await tester.scrollUntilVisible(
        find.text('Scenario'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(cardRect('Scenario').width, featured.width);
    });
  }

  testWidgets('everything written on the ground can be read there', (
    tester,
  ) async {
    activeRows = [_row('s1', 'truth_or_dare'), _row('s2', 'mirror')];
    cards['s1'] = _card(status: 'active', turn: 'me');
    cards['s2'] = _card(status: 'active', turn: 'partner');
    await pumpHub(tester);

    final ink = inkOnGround(tester, of: find.byType(GamesHubScreen));
    expect(ink.length, greaterThanOrEqualTo(8));
    for (final piece in ink) {
      expect(piece.contrast, greaterThanOrEqualTo(4.5), reason: piece.text);
    }
  });

  testWidgets('every card\'s words can be read on its colour', (tester) async {
    // Tall enough that every card is built: the list builds lazily.
    await pumpHub(tester, surface: tablet);

    final blocks = find.byKey(
      const ValueKey('game-hub-card-block'),
      skipOffstage: false,
    );
    expect(blocks, findsNWidgets(11));
    var pieces = 0;
    for (final block in blocks.evaluate()) {
      final colour =
          ((block.widget as DecoratedBox).decoration as BoxDecoration).color!;
      final words = find.descendant(
        of: find.byWidget(block.widget),
        matching: find.byType(RichText),
        skipOffstage: false,
      );
      for (final element in words.evaluate()) {
        var onTile = false;
        element.visitAncestorElements((ancestor) {
          if (ancestor.widget is DecoratedBox &&
              ancestor.widget.key == const ValueKey('game-hub-card-block')) {
            return false;
          }
          if (ancestor.widget is GameTile) {
            onTile = true;
            return false;
          }
          return true;
        });
        if (onTile) continue;
        final rich = element.widget as RichText;
        final text = rich.text.toPlainText();
        final ink = Color.alphaBlend(rich.text.style!.color!, colour);
        pieces++;
        expect(
          contrast(ink, colour),
          greaterThanOrEqualTo(4.5),
          reason: '"$text" on ${colour.toARGB32().toRadixString(16)}',
        );
      }
    }
    // Eleven titles and the featured tagline.
    expect(pieces, 12);
  });

  testWidgets('every card can be activated by a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHub(tester);

    final node = tester.getSemantics(find.bySemanticsLabel('Word Hunt'));
    expect(
      node,
      matchesSemantics(label: 'Word Hunt', isButton: true, hasTapAction: true),
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await settleRoute(tester);

    expect(find.text('opened:gameLanding:word_hunt'), findsOneWidget);
    handle.dispose();
  });

  group('coming back to the hub', () {
    testWidgets('reads the session list again', (tester) async {
      await pumpHub(tester);
      // The control: read once, and covering the hub does not read it.
      expect(listReads, 1);

      await tester.tap(find.text('Truth or Dare'));
      await settleRoute(tester);
      expect(find.text('opened:gameLanding:truth_or_dare'), findsOneWidget);
      expect(listReads, 1, reason: 'covered, not back yet');

      activeRows = [_row('s1', 'truth_or_dare')];
      await tester.tap(find.byType(BackButton));
      await settleBack(tester);

      expect(listReads, 2);
      expect(find.text('In play'), findsOneWidget);
    });

    testWidgets('re-reading does not throw with another reader of the list', (
      tester,
    ) async {
      // Invalidating while the tree builds throws when something else
      // watches the provider; the re-read waits for the frame to end.
      await pumpHub(
        tester,
        home: const Column(
          children: [Expanded(child: GamesHubScreen()), _OutsideReader()],
        ),
      );
      expect(find.text('outside:0'), findsOneWidget);

      await tester.tap(find.text('Truth or Dare'));
      await settleRoute(tester);
      activeRows = [_row('s1', 'truth_or_dare')];
      await tester.tap(find.byType(BackButton));
      await settleBack(tester);

      expect(tester.takeException(), isNull);
      expect(listReads, 2);
      expect(find.text('outside:1'), findsOneWidget);
    });
  });

  group('one screen per tap', () {
    testWidgets('two taps on a card in the same frame open one screen', (
      tester,
    ) async {
      await pumpHub(tester);

      await tester.tap(find.text('Truth or Dare'));
      await tester.tap(find.text('Truth or Dare'));
      await settleRoute(tester);

      expect(
        find.text('opened:gameLanding:truth_or_dare', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a tap one frame later lands on the opened screen', (
      tester,
    ) async {
      // The control for the test above: once the push has landed, the
      // pushed screen takes the tap.
      await pumpHub(tester);

      await tester.tap(find.text('Truth or Dare'));
      await tester.pump();
      await tester.tap(find.text('Truth or Dare'), warnIfMissed: false);
      await settleRoute(tester);

      expect(find.text('opened:gameLanding:truth_or_dare'), findsOneWidget);
      expect(
        find.text('opened:gameLanding:truth_or_dare', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('two taps on a game in play in the same frame open it once', (
      tester,
    ) async {
      activeRows = [_row('s1', 'truth_or_dare')];
      cards['s1'] = _card(status: 'active', turn: 'me');
      await pumpHub(tester);

      await tester.tap(sessionRow('s1'));
      await tester.tap(sessionRow('s1'));
      await tester.pump();
      expect(opened, [('truth_or_dare', 's1')]);

      // The control: the recorder opens nothing, so the hub is still in
      // front a frame later and the same tap opens it again.
      await tester.pump();
      await tester.tap(sessionRow('s1'));
      await tester.pump();
      expect(opened, [('truth_or_dare', 's1'), ('truth_or_dare', 's1')]);
    });
  });

  test('a card\'s words are dark where white would not read', () {
    // White is under 4.5:1 on every launch colour; GameTheme.tileInk is not.
    expect(GameColors.all, isNotEmpty);
    for (final colour in GameColors.all) {
      expect(contrast(hubCardInk(colour), colour), greaterThanOrEqualTo(4.5));
    }
    expect(hubCardInk(GameColors.comingSoon), GameTheme.onGround);
  });
}
