import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/start_this_or_that.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../platform/support/game_test_support.dart';
import '../platform/support/route_recorder.dart';
import 'support/this_or_that_fakes.dart';

/// A button that starts a game in [tone] and keeps what came back.
class _Starter extends ConsumerWidget {
  const _Starter({required this.tone, required this.results});

  final String tone;
  final List<String?> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            results.add(await startThisOrThat(context, ref, tone: tone));
          },
          child: const Text('start'),
        ),
      ),
    );
  }
}

void main() {
  late MockThisOrThatRepository repository;
  late List<String?> results;

  setUp(() {
    repository = MockThisOrThatRepository();
    results = [];
    createSessionAnswers(repository);
  });

  Future<void> pumpStarter(
    WidgetTester tester, {
    required String tone,
    String? relationshipId = 'rel-1',
  }) async {
    useSurface(tester, phone);
    await tester.pumpWidget(
      gameRouterHost(
        home: _Starter(tone: tone, results: results),
        prefs: await testPrefs(),
        overrides: [
          thisOrThatRepositoryProvider.overrideWithValue(repository),
          currentUserIdProvider.overrideWithValue('user-a'),
          currentRelationshipIdProvider.overrideWith(
            (ref) async => relationshipId,
          ),
        ],
      ),
    );
    await tester.pump();
  }

  Future<void> tapStart(WidgetTester tester) async {
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts a game in the tone asked for and returns its id', (
    tester,
  ) async {
    await pumpStarter(tester, tone: 'playful');
    await tapStart(tester);

    expect(results, ['new-session']);
    expect(createdTones(repository), ['playful']);
    // Playful asks nobody anything first.
    expect(find.text('Choose Intimate together'), findsNothing);
  });

  testWidgets('Intimate asks first, and "Not now" starts nothing', (
    tester,
  ) async {
    await pumpStarter(tester, tone: 'intimate');
    await tapStart(tester);

    expect(find.text('Choose Intimate together'), findsOneWidget);
    expect(
      find.text(
        'This tone includes adult questions for committed couples. Your '
        'partner will also be asked before the game begins.',
      ),
      findsOneWidget,
    );
    expect(results, isEmpty, reason: 'nothing is decided until they answer');

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Intimate together'), findsNothing);
    expect(results, [null]);
    verifyNoSessionCreated(repository);
  });

  testWidgets('Intimate continues after consent', (tester) async {
    await pumpStarter(tester, tone: 'intimate');
    await tapStart(tester);
    expect(find.text('Choose Intimate together'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(results, ['new-session']);
    expect(createdTones(repository), ['intimate']);
  });

  testWidgets('the Intimate question is dark, whatever the app is', (
    tester,
  ) async {
    // gameRouterHost is a light app, as the app is for most people. The
    // question is asked over a game, and a white dialog there glares.
    await pumpStarter(tester, tone: 'intimate');
    await tapStart(tester);

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    // The control: the page it was asked from is light.
    expect(
      Theme.of(tester.element(find.text('start'))).brightness,
      Brightness.light,
    );
    expect(Theme.of(tester.element(dialog)).brightness, Brightness.dark);
  });

  testWidgets('with no relationship it explains and starts nothing', (
    tester,
  ) async {
    await pumpStarter(tester, tone: 'playful', relationshipId: null);
    await tapStart(tester);

    expect(
      find.text('This game unlocks when a relationship is active.'),
      findsOneWidget,
    );
    expect(results, [null]);
    verifyNoSessionCreated(repository);
  });

  testWidgets('a failure is shown and returns null', (tester) async {
    when(
      () => repository.createSession(
        relationshipId: any(named: 'relationshipId'),
        initiatorId: any(named: 'initiatorId'),
        tone: any(named: 'tone'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenThrow(Exception('offline'));
    await pumpStarter(tester, tone: 'playful');
    await tapStart(tester);

    expect(find.text('The game could not start. Try again.'), findsOneWidget);
    expect(results, [null]);
    expect(createdTones(repository), ['playful']);
  });

  group('the nudge', () {
    final answered = DateTime.utc(2026, 11, 19, 10);

    /// Round 1 is over; round 2 is the current one. Partner A is the viewer.
    List<GameRound> rounds({
      bool viewerAnswered = true,
      bool partnerAnswered = false,
    }) {
      return [
        GameRound(
          id: 'r1',
          sessionId: 's1',
          roundNumber: 1,
          hasAnswerA: true,
          hasAnswerB: true,
          answerASubmittedAt: answered.subtract(const Duration(days: 1)),
          answerBSubmittedAt: answered.subtract(const Duration(days: 1)),
          bothAnswered: true,
        ),
        GameRound(
          id: 'r2',
          sessionId: 's1',
          roundNumber: 2,
          hasAnswerA: viewerAnswered,
          hasAnswerB: partnerAnswered,
          answerASubmittedAt: viewerAnswered ? answered : null,
          answerBSubmittedAt: partnerAnswered ? answered : null,
          bothAnswered: viewerAnswered && partnerAnswered,
        ),
      ];
    }

    test('a nudge is offered two hours after answering, not before', () {
      expect(
        thisOrThatCanRemind(
          rounds: rounds(),
          viewerIsPartnerA: true,
          now: answered.add(const Duration(minutes: 119)),
        ),
        isFalse,
      );
      expect(
        thisOrThatCanRemind(
          rounds: rounds(),
          viewerIsPartnerA: true,
          now: answered.add(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });

    test('no nudge when the partner has answered, or the viewer has not', () {
      final later = answered.add(const Duration(hours: 3));
      // The control: answered, partner not, long enough ago.
      expect(
        thisOrThatCanRemind(
          rounds: rounds(),
          viewerIsPartnerA: true,
          now: later,
        ),
        isTrue,
      );
      // Both answered: the round is over, nobody to nudge.
      expect(
        thisOrThatCanRemind(
          rounds: rounds(partnerAnswered: true),
          viewerIsPartnerA: true,
          now: later,
        ),
        isFalse,
      );
      // The viewer has not answered: it is their move, not the partner's.
      expect(
        thisOrThatCanRemind(
          rounds: rounds(viewerAnswered: false, partnerAnswered: true),
          viewerIsPartnerA: true,
          now: later,
        ),
        isFalse,
      );
      // The same rounds seen by partner B: B answered and A has not.
      expect(
        thisOrThatCanRemind(
          rounds: rounds(viewerAnswered: false, partnerAnswered: true),
          viewerIsPartnerA: false,
          now: later,
        ),
        isTrue,
      );
      expect(
        thisOrThatCanRemind(
          rounds: const [],
          viewerIsPartnerA: true,
          now: later,
        ),
        isFalse,
      );
    });
  });
}
