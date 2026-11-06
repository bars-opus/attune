// Spec 1 W9e, batch 3 (the controller's carries on the W9 B8 rulings):
// - D8: every Healing provider that holds account data starts again when the
//   account changes, hasActiveSoloHealingJourneyProvider included (owner
//   ruling), and every answer that lands after the change is dropped;
// - a support_offered answer hides that stage's AI text everywhere it shows
//   (on screen now, and the cached journey), and an older non-match never
//   un-hides a newer match (the sequence guard);
// - P-7 on the portrait: paused keeps today's path;
// - the card and the link meet the guidelines in the dark theme too.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/providers/healing_support_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_portrait_screen.dart';
import 'package:attune/features/healing/presentation/screens/healing_post_mortem_screen.dart';
import 'package:attune/features/healing/presentation/widgets/healing_support.dart';
import 'package:attune/features/healing/services/healing_generation_service.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import 'support/healing_fakes.dart';
import '../../../helpers/tap_in_reach.dart';

const _offered = {'status': 'support_offered'};
const _paused = {'status': 'paused'};
const _pmKey = (journeyId: 'j1', stage: HealingAiStage.postMortem);
const _ptKey = (journeyId: 'j1', stage: HealingAiStage.portrait);

final _signedIn = StateProvider<String?>((ref) => 'ama');

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Scaffold).first));

/// Each call waits for its own answer, so a test decides which lands first.
class _OrderedGeneration implements HealingGenerationService {
  final pending = <Completer<Map<String, dynamic>?>>[];

  Future<Map<String, dynamic>?> _next() {
    final c = Completer<Map<String, dynamic>?>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<Map<String, dynamic>?> generatePostMortem({
    required String journeyId,
  }) => _next();

  @override
  Future<Map<String, dynamic>?> generatePortrait({required String journeyId}) =>
      _next();
}

/// The brief's fake, plus the solo-journey check, the start and a count of
/// journey reads.
class _Repo extends FakeHealingRepository {
  final active = <String, bool>{};
  final started = <String>[];
  int journeyReads = 0;

  @override
  Future<bool> hasActiveSoloJourney() async {
    final who = account;
    if (who != 'ama') await hold?.future;
    return active[who] ?? false;
  }

  @override
  Future<HealingJourney> getOrCreateJourney({
    String? relationshipId,
    required DateTime breakupAt,
    required String breakupAtSource,
  }) async {
    started.add(account);
    return testJourney(userId: account);
  }

  @override
  Future<HealingJourney?> getLatestJourney() {
    journeyReads++;
    return super.getLatestJourney();
  }
}

List<Override> _overrides(
  HealingGenerationService gen,
  FakeHealingRepository repo,
) => [
  healingGenerationServiceProvider.overrideWithValue(gen),
  healingRepositoryProvider.overrideWithValue(repo),
  healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
];

/// What Conversations and the Me home do at tap time: the journey if one is
/// under way, else the self-report sheet.
class _OpenHealing extends ConsumerStatefulWidget {
  const _OpenHealing();

  @override
  ConsumerState<_OpenHealing> createState() => _OpenHealingState();
}

class _OpenHealingState extends ConsumerState<_OpenHealing> {
  String _said = '';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () async {
            setState(() => _said = 'waiting');
            final active = await ref.read(
              hasActiveSoloHealingJourneyProvider.future,
            );
            if (!mounted) return;
            setState(() => _said = active ? 'journey' : 'sheet');
          },
          child: const Text('Open Healing'),
        ),
        Text('said: $_said'),
      ],
    ),
  );
}

ProviderContainer _bare(_Repo repo) {
  final c = ProviderContainer(
    overrides: [
      healingRepositoryProvider.overrideWithValue(repo),
      healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('D8: the solo-journey check and the start belong to the account', () {
    testWidgets('the next account never gets the last one\'s answer while its '
        'read is out (owner ruling)', (t) async {
      final repo = _Repo()..active['ama'] = true;
      await pumpFlowScreen(
        t,
        () => const _OpenHealing(),
        overrides: [
          healingRepositoryProvider.overrideWithValue(repo),
          healingAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
        ],
      );
      await t.tap(find.text('Open Healing'));
      await t.pumpAndSettle();
      expect(find.text('said: journey'), findsOneWidget);

      repo
        ..account = 'kofi'
        ..hold = Completer<void>();
      _container(t).read(_signedIn.notifier).state = 'kofi';
      await t.pump();
      await t.tap(find.text('Open Healing'));
      // Frame by frame while Kofi's read is out: never Ama's answer.
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('said: journey'), findsNothing, reason: 'frame $i');
        expect(find.text('said: waiting'), findsOneWidget, reason: 'frame $i');
      }
      repo.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('said: sheet'), findsOneWidget);
    });

    test('Healing\'s user id is the signed-in account', () {
      final c = _bare(_Repo());
      expect(c.read(currentUserIdProvider), 'ama');
      c.read(_signedIn.notifier).state = 'kofi';
      expect(c.read(currentUserIdProvider), 'kofi');
    });

    test('a partner on the same phone starts their own journey, not the '
        'cached start', () async {
      final repo = _Repo();
      final c = _bare(repo);
      final context = (
        relationshipId: 'r1',
        breakupAt: DateTime.utc(2026, 10),
        breakupAtSource: 'relationship',
      );
      await c.read(startHealingJourneyProvider(context).future);
      repo.account = 'kofi';
      c.read(_signedIn.notifier).state = 'kofi';
      await c.read(startHealingJourneyProvider(context).future);
      expect(repo.started, ['ama', 'kofi']);
    });
  });

  group('D8: every answer that lands after the account changed is dropped', () {
    testWidgets('post-mortem: a completed answer is neither shown nor saved', (
      t,
    ) async {
      final gen = FakeHealingGeneration([
        {
          'status': 'completed',
          'observation': 'Written for the last account.',
          'confidence': 'low',
          'reflection_prompt': null,
        },
      ])..gate = Completer<void>();
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        () => HealingPostMortemScreen(journey: testJourney()),
        overrides: _overrides(gen, repo),
      );
      await tapInReach(t, find.text('Generate reflection'));
      await t.pump();
      _container(t).read(_signedIn.notifier).state = 'kofi';
      await t.pump();
      gen.gate!.complete();
      await t.pump();
      await t.pump();
      expect(find.text('Written for the last account.'), findsNothing);
      expect(repo.saved, isEmpty);
    });

    testWidgets('portrait: a paused answer records nothing', (t) async {
      final gen = FakeHealingGeneration([_paused])..gate = Completer<void>();
      final repo = FakeHealingRepository();
      await pumpFlowScreen(
        t,
        () => HealingPortraitScreen(journey: testJourney(stage: 4)),
        overrides: _overrides(gen, repo),
      );
      await tapInReach(t, find.text('Generate portrait'));
      await t.pump();
      _container(t).read(_signedIn.notifier).state = 'kofi';
      await t.pump();
      gen.gate!.complete();
      await t.pump();
      await t.pump();
      expect(repo.saved, isEmpty);
    });
  });

  group(
    'the sequence guard: an older non-match never un-hides a newer match',
    () {
      Future<void> overlap(
        WidgetTester t, {
        required Widget Function() screen,
        required String generate,
        required Map<String, dynamic> olderAnswer,
        required String olderText,
        required HealingSupportKey key,
      }) async {
        final gen = _OrderedGeneration();
        final repo = FakeHealingRepository();
        final h = await pumpFlowScreen(
          t,
          screen,
          overrides: _overrides(gen, repo),
        );
        // The first request is sent, and the person leaves while it is out.
        await tapInReach(t, find.text(generate));
        await t.pump();
        final c = _container(t);
        h.router.go('/elsewhere');
        await t.pumpAndSettle();
        // Back on the stage, a second request: the check matches.
        h.router.go('/test');
        await t.pumpAndSettle();
        await tapInReach(t, find.text(generate));
        await t.pump();
        expect(gen.pending, hasLength(2));
        gen.pending[1].complete(_offered);
        await t.pumpAndSettle();
        expect(find.text(supportCardText), findsOneWidget);
        // Then the older request's ordinary answer lands.
        gen.pending[0].complete(olderAnswer);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text(supportCardText), findsOneWidget);
        expect(find.text(olderText), findsNothing);
        expect(c.read(healingSupportProvider).hidden, {key});
        expect(repo.saved, isEmpty);
      }

      testWidgets('post-mortem', (t) async {
        await overlap(
          t,
          screen: () => HealingPostMortemScreen(journey: testJourney()),
          generate: 'Generate reflection',
          olderAnswer: {
            'status': 'completed',
            'observation': 'An older answer.',
            'confidence': 'low',
            'reflection_prompt': null,
          },
          olderText: 'An older answer.',
          key: _pmKey,
        );
      });

      testWidgets('portrait', (t) async {
        await overlap(
          t,
          screen: () => HealingPortraitScreen(journey: testJourney(stage: 4)),
          generate: 'Generate portrait',
          olderAnswer: {
            'status': 'completed',
            'portrait': 'An older portrait.',
            'reflection_prompt': null,
          },
          olderText: 'An older portrait.',
          key: _ptKey,
        );
      });

      test('in the state: numbered by when sent, a match by when it lands', () {
        final c = _bare(_Repo());
        final s = c.read(healingSupportProvider.notifier);
        final first = s.begin();
        final second = s.begin();
        s.offer(_pmKey);
        expect(s.isStale(_pmKey, first), isTrue);
        expect(s.isStale(_pmKey, second), isTrue);
        expect(s.isStale(_ptKey, first), isFalse); // the other stage
        expect(s.isStale(_pmKey, s.begin()), isFalse); // sent after the match
      });

      test('an account change forgets the matches', () {
        final c = _bare(_Repo());
        final s = c.read(healingSupportProvider.notifier);
        final first = s.begin();
        s.offer(_pmKey);
        c.read(_signedIn.notifier).state = 'kofi';
        c.read(healingSupportProvider);
        expect(s.account, 'kofi');
        expect(s.isStale(_pmKey, first), isFalse);
      });
    },
  );

  group('a match hides the stage\'s AI text everywhere it shows', () {
    testWidgets('post-mortem: the text on screen now, also after Not now', (
      t,
    ) async {
      await pumpFlowScreen(
        t,
        () => HealingPostMortemScreen(
          journey: testJourney(
            postMortemStatus: 'completed',
            postMortemObservation: 'An observation on screen.',
          ),
        ),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
        ),
      );
      expect(find.text('An observation on screen.'), findsOneWidget);
      // A match from another request for this stage.
      _container(t).read(healingSupportProvider.notifier).offer(_pmKey);
      await t.pumpAndSettle();
      expect(find.text('An observation on screen.'), findsNothing);
      expect(find.text(supportCardText), findsOneWidget);
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text('An observation on screen.'), findsNothing);
      expect(
        find.text(
          'There is not enough information for a grounded reflection yet.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue \u2192'), findsOneWidget);
    });

    testWidgets('portrait: the text on screen now, also after Not now', (
      t,
    ) async {
      await pumpFlowScreen(
        t,
        () => HealingPortraitScreen(
          journey: testJourney(
            stage: 4,
            portraitStatus: 'completed',
            portraitText: 'A portrait on screen.',
          ),
        ),
        overrides: _overrides(
          FakeHealingGeneration([]),
          FakeHealingRepository(),
        ),
      );
      expect(find.text('A portrait on screen.'), findsOneWidget);
      _container(t).read(healingSupportProvider.notifier).offer(_ptKey);
      await t.pumpAndSettle();
      expect(find.text('A portrait on screen.'), findsNothing);
      await tapInReach(t, find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text('A portrait on screen.'), findsNothing);
      expect(find.text('Save portrait \u2192'), findsNothing);
      expect(find.text('No portrait available yet.'), findsOneWidget);
      expect(find.text('Continue \u2192'), findsOneWidget);
    });

    test('the cached journey is read again', () async {
      final repo = _Repo()..latest['ama'] = testJourney();
      final c = _bare(repo);
      c.listen(healingJourneyProvider, (_, __) {});
      await c.read(healingJourneyProvider.future);
      expect(repo.journeyReads, 1);
      c.read(healingSupportProvider.notifier).offer(_pmKey);
      await c.read(healingJourneyProvider.future);
      expect(repo.journeyReads, 2);
    });

    test('a wipe forgets the matches too', () async {
      final c = _bare(_Repo());
      final s = c.read(healingSupportProvider.notifier);
      final first = s.begin();
      s.offer(_pmKey);
      await HealingSupportMemory.clear();
      expect(s.isStale(_pmKey, first), isFalse);
      expect(c.read(healingSupportProvider).hidden, isEmpty);
    });
  });

  testWidgets('P-7, portrait: paused keeps today\'s path', (t) async {
    final repo = FakeHealingRepository();
    await pumpFlowScreen(
      t,
      () => HealingPortraitScreen(journey: testJourney(stage: 4)),
      overrides: _overrides(FakeHealingGeneration([_paused]), repo),
    );
    await tapInReach(t, find.text('Generate portrait'));
    await t.pumpAndSettle();
    expect(repo.saved, ['portrait:insufficient_evidence']);
    expect(find.text('No portrait available yet.'), findsOneWidget);
    expect(find.text('Continue \u2192'), findsOneWidget);
    expect(find.text(supportCardText), findsNothing);
  });

  testWidgets('the card and the link meet the guidelines in the dark theme, '
      'at 1.0 and 2.0, and right to left', (t) async {
    for (final (scale, direction) in [
      (1.0, TextDirection.ltr),
      (2.0, TextDirection.ltr),
      (1.0, TextDirection.rtl),
    ]) {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearAllTestValues);
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder:
                (context, child) => Directionality(
                  textDirection: direction,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.0,
                    child: child!,
                  ),
                ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    HealingSupportCard(onNotNow: () {}),
                    const HealingNeedSupportLink(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        Theme.of(t.element(find.text(supportCardText))).brightness,
        Brightness.dark,
      );
      await expectFlowGuidelines(t);
    }
  });
}
