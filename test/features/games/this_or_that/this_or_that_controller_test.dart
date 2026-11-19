import 'dart:async';

import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/platform/shell/game_landing_page.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:attune/features/games/presentation/providers/game_partner_name_provider.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    as hub;
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../platform/support/game_test_support.dart';
import '../platform/support/route_recorder.dart';
import 'support/this_or_that_fakes.dart';

GameCardState _card(
  String status, {
  bool? viewerAnswered,
  bool? partnerAnswered,
}) {
  return GameCardState(
    gameType: 'this_or_that',
    status: status,
    currentTurnUserId: null,
    winnerUserId: null,
    currentRound: 3,
    totalRounds: 10,
    viewerAnswered: viewerAnswered,
    partnerAnswered: partnerAnswered,
  );
}

/// Calls watchLanding from build, as the shell does, and says what it read.
class _Probe extends ConsumerWidget {
  const _Probe(this.onState);

  final void Function(
    GameLandingState state,
    BuildContext context,
    WidgetRef ref,
  )
  onState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = thisOrThatController.watchLanding(ref);
    onState(state, context, ref);
    return Scaffold(body: Center(child: Text('status:${state.status.name}')));
  }
}

const thisOrThatController = ThisOrThatController();

void main() {
  late MockThisOrThatRepository repository;
  late int reads;

  /// What the session provider answers on each read, oldest first. The
  /// last answer repeats.
  late List<ThisOrThatSession?> sessions;
  late List<Map<String, dynamic>> recent;
  late Map<String, GameCardState?> cards;
  late List<GameRound> rounds;
  late StreamController<void> events;
  late GameLandingState seen;
  late BuildContext probeContext;
  late WidgetRef probeRef;

  setUp(() {
    repository = MockThisOrThatRepository();
    createSessionAnswers(repository);
    when(
      () => repository.sendReminder(any(), any()),
    ).thenAnswer((_) async => true);
    reads = 0;
    sessions = [null];
    recent = [];
    cards = {};
    rounds = [];
  });

  List<Override> overrides() => [
    thisOrThatRepositoryProvider.overrideWithValue(repository),
    currentUserIdProvider.overrideWithValue('user-a'),
    currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
    hub.currentUserIdProvider.overrideWithValue('user-a'),
    activeThisOrThatSessionProvider.overrideWith((ref) async {
      final answer =
          sessions[reads < sessions.length ? reads : sessions.length - 1];
      reads++;
      return answer;
    }),
    hub.recentGamesProvider.overrideWith((ref) async => recent),
    hub.gameSessionEventsProvider.overrideWith((ref) => events.stream),
    gameCardProvider.overrideWith((ref, id) => Stream.value(cards[id])),
    gamePartnerNameProvider.overrideWith((ref) async => 'Ama'),
    relationshipMembersProvider.overrideWith(
      (ref, id) async => (userA: 'user-a', userB: 'user-b'),
    ),
    sessionRoundsProvider.overrideWith((ref, id) async => rounds),
  ];

  void listenToEvents() {
    events = StreamController<void>();
    addTearDown(events.close);
  }

  Future<void> pumpProbe(WidgetTester tester) async {
    useSurface(tester, phone);
    listenToEvents();
    await tester.pumpWidget(
      gameRouterHost(
        home: _Probe((state, context, ref) {
          seen = state;
          probeContext = context;
          probeRef = ref;
        }),
        prefs: await testPrefs(),
        overrides: overrides(),
      ),
    );
    // The control for every test here: the session still on its way is
    // loading.
    expect(seen.status, GameLandingStatus.loading);
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    useSurface(tester, phone);
    listenToEvents();
    await tester.pumpWidget(
      gameRouterHost(
        home: const GameLandingPage(gameType: 'this_or_that'),
        prefs: await testPrefs(),
        overrides: overrides(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the landing page until the row reading [text] is on screen.
  Future<void> scrollTo(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  List<String> titles() {
    final entries = thisOrThatController.entries(probeContext, probeRef, seen);
    return [for (final entry in entries) entry.title];
  }

  Future<void> tapEntry(WidgetTester tester, String title) async {
    final entries = thisOrThatController.entries(probeContext, probeRef, seen);
    expect(entries, isNotEmpty);
    await entries.firstWhere((entry) => entry.title == title).onTap!(
      probeContext,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no game: Play, with the five tones first', (tester) async {
    await pumpProbe(tester);

    expect(seen.status, GameLandingStatus.fresh);
    expect(titles(), [
      'Connecting',
      'Romantic',
      'Playful',
      'Spicy',
      'Intimate',
      'Your questions',
      'Past games',
      'From the community',
    ]);
    final entries = thisOrThatController.entries(probeContext, probeRef, seen);
    expect(entries.first.subtitle, 'Easy questions that bring you closer');
  });

  testWidgets('a game in progress hides the tones and keeps the rest', (
    tester,
  ) async {
    sessions = [thisOrThatSession()];
    cards = {'s1': _card('active')};
    await pumpProbe(tester);

    expect(seen.status, GameLandingStatus.yourTurn);
    expect(seen.sessionId, 's1');
    expect(seen.caption, 'Round 3 of 10');
    expect(titles(), ['Your questions', 'Past games', 'From the community']);
  });

  testWidgets('Play starts a Connecting game and opens it', (tester) async {
    await pumpProbe(tester);
    expect(seen.status, GameLandingStatus.fresh);

    await thisOrThatController.onPrimary(probeContext, probeRef, seen);
    await tester.pumpAndSettle();

    expect(createdTones(repository), ['connecting']);
    expect(
      find.text('opened:thisOrThatSessionRouter:new-session'),
      findsOneWidget,
    );
  });

  testWidgets('a tone row starts a game in that tone', (tester) async {
    await pumpProbe(tester);

    await tapEntry(tester, 'Playful');

    expect(createdTones(repository), ['playful']);
    expect(
      find.text('opened:thisOrThatSessionRouter:new-session'),
      findsOneWidget,
    );
  });

  testWidgets('Your turn opens the game in progress and starts nothing', (
    tester,
  ) async {
    sessions = [thisOrThatSession()];
    cards = {'s1': _card('active')};
    await pumpProbe(tester);
    expect(seen.status, GameLandingStatus.yourTurn);

    await thisOrThatController.onPrimary(probeContext, probeRef, seen);
    await tester.pumpAndSettle();

    verifyNoSessionCreated(repository);
    expect(find.text('opened:thisOrThatSessionRouter:s1'), findsOneWidget);
  });

  testWidgets('after a finished game the button offers another', (
    tester,
  ) async {
    recent = [
      {'id': 'old', 'game_type': 'this_or_that', 'status': 'completed'},
      {'id': 'older', 'game_type': 'truth_or_dare', 'status': 'completed'},
    ];
    await pumpProbe(tester);

    expect(seen.status, GameLandingStatus.finished);
    // Play again starts a new game; it does not reopen the old one.
    await thisOrThatController.onPrimary(probeContext, probeRef, seen);
    await tester.pumpAndSettle();
    expect(createdTones(repository), ['connecting']);
    expect(
      find.text('opened:thisOrThatSessionRouter:new-session'),
      findsOneWidget,
    );
  });

  testWidgets('another game finishing last is not this one finishing', (
    tester,
  ) async {
    // The control for the test above: only This or That's own last game
    // makes it Play again.
    recent = [
      {'id': 'older', 'game_type': 'truth_or_dare', 'status': 'completed'},
      {'id': 'old', 'game_type': 'this_or_that', 'status': 'completed'},
    ];
    await pumpProbe(tester);

    expect(seen.status, GameLandingStatus.fresh);
  });

  testWidgets('coming back from the game re-reads where it stands', (
    tester,
  ) async {
    // Review Focus 3, through the real page. The session provider answers
    // 'none' the first time and an active session the second.
    sessions = [null, thisOrThatSession()];
    cards = {'s1': _card('active')};
    await pumpPage(tester);
    expect(reads, 1);
    expect(find.text('Play'), findsOneWidget);

    await tester.tap(find.byType(GamePrimaryButton));
    await tester.pumpAndSettle();
    expect(
      find.text('opened:thisOrThatSessionRouter:new-session'),
      findsOneWidget,
    );
    expect(reads, 1, reason: 'covered, not back yet');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('ROUND 3 OF 10'), findsOneWidget);
  });

  testWidgets('onResume re-reads the session and the finished games', (
    tester,
  ) async {
    sessions = [null, thisOrThatSession()];
    cards = {'s1': _card('active')};
    await pumpProbe(tester);
    expect(seen.status, GameLandingStatus.fresh);
    expect(reads, 1);

    thisOrThatController.onResume(probeRef);
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(seen.status, GameLandingStatus.yourTurn);
    expect(find.text('status:yourTurn'), findsOneWidget);
  });

  testWidgets('a partner\'s move refreshes it', (tester) async {
    // Review Focus 2.
    sessions = [
      null,
      thisOrThatSession(initiatorId: 'user-b', status: 'invited'),
    ];
    cards = {'s1': _card('invited')};
    await pumpProbe(tester);
    expect(reads, 1);
    expect(seen.status, GameLandingStatus.fresh);

    events.add(null);
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(seen.status, GameLandingStatus.invited);
    expect(seen.sessionId, 's1');
  });

  testWidgets('the rows open the question decks, past games and the '
      'community feed', (tester) async {
    await pumpProbe(tester);

    const expected = {
      'Your questions': 'opened:thisOrThatCustomList:',
      'Past games': 'opened:thisOrThatSessionHistory:',
      'From the community': 'opened:communityFeed:This or That',
    };
    for (final row in expected.entries) {
      await tapEntry(tester, row.key);
      expect(find.text(row.value), findsOneWidget, reason: row.key);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('status:fresh'), findsOneWidget);
    }
    verifyNoSessionCreated(repository);
  });

  group('the nudge', () {
    /// Round 3: the viewer (partner A) answered three hours ago, Ama has not.
    List<GameRound> waitingRounds() => [
      GameRound(
        id: 'r3',
        sessionId: 's1',
        roundNumber: 3,
        hasAnswerA: true,
        hasAnswerB: false,
        answerASubmittedAt: DateTime.now().subtract(const Duration(hours: 3)),
        bothAnswered: false,
      ),
    ];

    testWidgets('a nudge is sent, and says so', (tester) async {
      sessions = [thisOrThatSession()];
      cards = {
        's1': _card('active', viewerAnswered: true, partnerAnswered: false),
      };
      rounds = waitingRounds();
      await pumpProbe(tester);
      expect(seen.status, GameLandingStatus.waiting);
      expect(seen.canRemind, isTrue);

      await thisOrThatController.onRemind(probeContext, probeRef, seen);
      await tester.pump();

      verify(() => repository.sendReminder('s1', 'user-a')).called(1);
      expect(find.text('A gentle nudge was sent to Ama.'), findsOneWidget);
    });

    testWidgets('a nudge that fails says so', (tester) async {
      when(
        () => repository.sendReminder(any(), any()),
      ).thenThrow(Exception('too soon'));
      sessions = [thisOrThatSession()];
      cards = {
        's1': _card('active', viewerAnswered: true, partnerAnswered: false),
      };
      rounds = waitingRounds();
      await pumpProbe(tester);
      expect(seen.canRemind, isTrue);

      await thisOrThatController.onRemind(probeContext, probeRef, seen);
      await tester.pump();

      expect(find.text('The reminder could not be sent yet.'), findsOneWidget);
      expect(find.text('A gentle nudge was sent to Ama.'), findsNothing);
    });

    testWidgets('an invitation waiting to be accepted offers no nudge', (
      tester,
    ) async {
      // The viewer invited Ama, who has not said yes: waiting, but there is
      // no round to nudge about. The rounds would say otherwise, so only
      // the session's status keeps the nudge away. Its control is the
      // active session in 'a nudge is sent, and says so'.
      sessions = [thisOrThatSession(status: 'invited')];
      cards = {'s1': _card('invited')};
      rounds = waitingRounds();
      await pumpProbe(tester);

      expect(seen.status, GameLandingStatus.waiting);
      expect(seen.canRemind, isFalse);
    });
  });

  group('one start at a time, on the page', () {
    testWidgets('a tone row starts a game in that tone', (tester) async {
      // The control for the test below.
      await pumpPage(tester);
      await scrollTo(tester, '3. Playful');

      await tester.tap(find.text('3. Playful'));
      await tester.pumpAndSettle();

      expect(createdTones(repository), ['playful']);
      expect(
        find.text('opened:thisOrThatSessionRouter:new-session'),
        findsOneWidget,
      );
    });

    testWidgets('taps while an Intimate game is being created start nothing '
        'else', (tester) async {
      final creating = Completer<ThisOrThatSession>();
      when(
        () => repository.createSession(
          relationshipId: any(named: 'relationshipId'),
          initiatorId: any(named: 'initiatorId'),
          tone: any(named: 'tone'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenAnswer((_) => creating.future);
      await pumpPage(tester);
      await scrollTo(tester, '5. Intimate');
      // The other row and the button this test taps are still on screen,
      // so a tap below that does nothing has landed.
      expect(find.text('3. Playful').hitTestable(), findsOneWidget);
      expect(find.byType(GamePrimaryButton).hitTestable(), findsOneWidget);

      await tester.tap(find.text('5. Intimate'));
      // Not settled: the button spins from the tap on.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Choose Intimate together'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      // Not settled: the button spins while the game is being created.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Choose Intimate together'), findsNothing);

      await tester.tap(find.text('3. Playful'), warnIfMissed: false);
      await tester.tap(find.byType(GamePrimaryButton), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(createdTones(repository), ['intimate']);
      expect(find.text('Choose Intimate together'), findsNothing);

      creating.complete(
        thisOrThatSession(
          id: 'new-session',
          tone: 'intimate',
          status: 'invited',
        ),
      );
      await tester.pumpAndSettle();

      // One game screen, not one per tap.
      expect(
        find.text(
          'opened:thisOrThatSessionRouter:new-session',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });
  });
}
