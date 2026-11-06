// Spec 1 W5 (§3.8 AU1-AU6, §2.2, §2.3, §3.14): one question per screen,
// every one skippable, "2 of 5" (AU3 only when Married), each answer saved
// as it is given, no future dates, the anniversary's missing day asked
// for, refusals in the app's words, offline answers kept on this phone;
// goldens at 1.0, 1.3, 2.0 and right to left; the three guidelines.
import 'dart:async';

import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/couple_profile/presentation/widgets/about_us_choice.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show coupleProfileEnabledProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';

const _uid = 'u-about';
const _rel = 'rel-about';
final _today = DateTime(2026, 11, 2, 10);

List<Override> _overrides(
  FakeCoupleProfileServer server, {
  bool enabled = true,
  String? coupleName,
}) => [
  coupleProfileEnabledProvider.overrideWithValue(enabled),
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
  coupleNameProvider.overrideWith((ref, id) async => coupleName),
];

Widget _flow(
  AboutUsTarget target, {
  AboutUsQuestion? only,
  VoidCallback? onDone,
  String? partnerName,
}) => AboutUsQuestionFlow(
  target: target,
  only: only,
  partnerName: partnerName,
  now: () => _today,
  onDone: onDone ?? () {},
);

Future<void> _choose(WidgetTester tester, String fieldKey, String item) async {
  await tapInReach(tester, find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// As [_choose], for an item further down an open menu than it shows.
Future<void> _chooseFar(
  WidgetTester tester,
  String fieldKey,
  String item, {
  double delta = 100,
}) async {
  await tapInReach(tester, find.byKey(ValueKey(fieldKey)));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text(item).hitTestable(),
    delta,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

const _stopTitle = 'Your anniversary reminder will stop';

Future<void> _continue(WidgetTester tester, [String label = 'Continue']) async {
  await tester.ensureVisible(find.text(label));
  await tapInReach(tester, find.text(label));
  await tester.pumpAndSettle();
}

Map<String, dynamic>? _lastPatch(FakeCoupleProfileServer server) {
  final updates = server.calls.where((c) => c.$1.startsWith('update_'));
  if (updates.isEmpty) return null;
  return Map<String, dynamic>.from(updates.last.$2!['p_patch'] as Map);
}

void main() {
  testWidgets('AU1-AU6 in order, each saved as given; AU3 only when Married', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer();
    var done = false;
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), onDone: () => done = true),
      overrides: _overrides(server),
    );
    expect(
      find.text('How would you describe where you two are?'),
      findsOneWidget,
    );
    expect(find.text('1 of 5'), findsOneWidget);
    expect(find.bySemanticsLabel('Question 1 of 5'), findsOneWidget);
    expect(
      find.text('Any kind of marriage: customary, religious or civil.'),
      findsOneWidget,
    );
    await tapInReach(tester, find.text('Married'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(_lastPatch(server), {'stage': 'married', 'stage_words': null});
    expect(server.calls.last.$1, 'update_my_couple_profile_draft');

    // AU2, now "2 of 6": Married adds AU3.
    expect(find.text('When did you two get together?'), findsOneWidget);
    expect(find.text('2 of 6'), findsOneWidget);
    await _choose(tester, 'about-us-since-month', 'October');
    await _choose(tester, 'about-us-since-year', '2019');
    await _continue(tester);
    expect(_lastPatch(server), {
      'together_since': '2019-10-01',
      'together_since_precision': 'month',
    });

    // AU3, skipped: nothing saved.
    expect(find.text('What year did you marry?'), findsOneWidget);
    final before = server.calls.length;
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(server.calls.length, before, reason: 'Skip writes nothing');

    // AU4.
    expect(find.text('Where do you two live?'), findsOneWidget);
    await tester.tap(find.text('Apart, nearby'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(_lastPatch(server), {'living': 'apart_nearby'});

    // AU5 with an age band.
    await tapInReach(tester, find.text('Yes'));
    await tester.pumpAndSettle();
    expect(find.text('Their ages (optional)'), findsOneWidget);
    await tapInReach(tester, find.text('18+'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(_lastPatch(server), {
      'children': 'yes',
      'child_age_bands': ['18plus'],
    });

    // AU6: the month is known, so only the day is asked for, in the same write.
    expect(find.text('6 of 6'), findsOneWidget);
    await tapInReach(tester, find.text('The day you got together'));
    await tester.pumpAndSettle();
    expect(find.text('What day was it?'), findsOneWidget);
    await _choose(tester, 'about-us-anniversary-day', '14');
    await _continue(tester, 'Done');
    expect(_lastPatch(server), {
      'together_since': '2019-10-14',
      'together_since_precision': 'day',
      'anniversary_source': 'together_since',
    });
    expect(done, isTrue);
  });

  testWidgets('a future date is refused on the phone, and said', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer();
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.together),
      overrides: _overrides(server),
    );
    expect(find.text('Skip'), findsNothing, reason: 'one question: Save');
    expect(
      find.textContaining(RegExp(r'^\d+ of \d+$')),
      findsNothing,
      reason: 'no step dots',
    );
    await _choose(tester, 'about-us-since-month', 'December');
    await _choose(tester, 'about-us-since-year', '2026');
    await _continue(tester, 'Save');
    expect(find.text('That date is in the future.'), findsOneWidget);
    expect(server.count('update_my_couple_profile_draft'), 0);
  });

  testWidgets('a refusal is the app\'s words; the question stays', (
    tester,
  ) async {
    final server =
        FakeCoupleProfileServer()
          ..failUpdates = FakeCoupleProfileServer.refusal(
            'couple_profile:anniversary_needs_day',
          );
    await pumpFlowScreen(
      tester,
      () =>
          _flow(const AboutUsTarget.shared(_rel), only: AboutUsQuestion.living),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('Together'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    expect(
      find.text(
        'Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.',
      ),
      findsOneWidget,
    );
    expect(find.text('Where do you two live?'), findsOneWidget);
  });

  testWidgets('offline: kept on this phone for this account, and it moves on', (
    tester,
  ) async {
    final server =
        FakeCoupleProfileServer()..failUpdates = TimeoutException('offline');
    var done = false;
    final harness = await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.living,
        onDone: () => done = true,
      ),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('Long distance'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    expect(done, isTrue);
    final outbox = AboutUsOutbox(harness.prefs, userId: _uid);
    expect(outbox.pending(const AboutUsTarget.shared(_rel))!.values, {
      'living': 'long_distance',
    });
  });

  testWidgets('"More about this" says the draft is yours until they join', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), partnerName: 'Ama'),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await tester.ensureVisible(find.text('More about this'));
    await tester.tap(find.text('More about this'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Either of you can change these. It's never used to score or type you.",
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Before Ama joins, your answers are a draft only you can see. When Ama joins, your answers become your shared About us.',
      ),
      findsOneWidget,
    );
  });

  // Batch 5 (batch-4 re-review N-2): the "your partner" fallback, exactly.
  testWidgets('"More about this" without a name says "your partner"', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft()),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await tester.ensureVisible(find.text('More about this'));
    await tester.tap(find.text('More about this'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Before your partner joins, your answers are a draft only you can see. When your partner joins, your answers become your shared About us.',
      ),
      findsOneWidget,
    );
  });

  // Batch 5 (ruling): AU2's helper names the couple by their chat name
  // (coupleNameProvider); without one (a draft, or no name chosen yet) it
  // says "Use whichever date feels right." (ruling M-1); never "you both".
  testWidgets('AU2\'s helper names the couple, never "you both"', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.together,
      ),
      overrides: _overrides(
        FakeCoupleProfileServer(),
        coupleName: 'The Mensahs',
      ),
    );
    expect(
      find.text('Use whichever date feels right to The Mensahs.'),
      findsOneWidget,
    );
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.together),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    // Ruling M-1: no couple name, no couple noun.
    expect(find.text('Use whichever date feels right.'), findsOne);
    expect(find.textContaining('couples'), findsNothing);
    expect(find.textContaining('you both'), findsNothing);
  });

  // Fix round 1 (review I-1): an answer is one node a screen reader can
  // activate (B4's AboutUsChoice).
  testWidgets('screen readers: an AU1 answer has a tap action and selects', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final server = FakeCoupleProfileServer();
    await pumpFlowScreen(
      tester,
      () =>
          _flow(const AboutUsTarget.shared(_rel), only: AboutUsQuestion.stage),
      overrides: _overrides(server),
    );
    final choice = find.bySemanticsLabel(RegExp('^Engaged'));
    expect(choice, findsOneWidget);
    expect(
      tester
          .getSemantics(choice)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.semantics.tap(find.semantics.byLabel(RegExp('^Engaged')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Engaged')))
          .getSemanticsData()
          .hasFlag(SemanticsFlag.isChecked),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('the guidelines hold on AU1 and AU5 (chips)', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft()),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await expectFlowGuidelines(tester);
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.children),
      overrides: _overrides(
        FakeCoupleProfileServer(
          profiles: {'draft': aboutUsJson(draft: true, children: 'yes')},
        ),
      ),
    );
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  for (final (name, question, profile) in [
    (
      'about_us_au1',
      AboutUsQuestion.stage,
      aboutUsJson(draft: true, stage: 'other', stageWords: 'Courting'),
    ),
    (
      'about_us_au2',
      AboutUsQuestion.together,
      aboutUsJson(draft: true, togetherSince: '2019-10-14', precision: 'day'),
    ),
    (
      'about_us_au3',
      AboutUsQuestion.married,
      aboutUsJson(
        draft: true,
        stage: 'married',
        ceremonies: [
          {'year': 1999, 'label': 'customary'},
          {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
        ],
      ),
    ),
    (
      'about_us_au5',
      AboutUsQuestion.children,
      aboutUsJson(draft: true, children: 'yes', bands: ['13to17', '18plus']),
    ),
    (
      'about_us_au6',
      AboutUsQuestion.anniversary,
      aboutUsJson(
        draft: true,
        stage: 'married',
        togetherSince: '2019-10-01',
        precision: 'month',
        ceremonies: [
          {'year': 1999, 'label': 'customary'},
        ],
      ),
    ),
  ]) {
    testWidgets('goldens: $name', (tester) async {
      await expectFlowGoldens(
        tester,
        name,
        () => _flow(const AboutUsTarget.draft(), only: question),
        overrides: _overrides(
          FakeCoupleProfileServer(profiles: {'draft': profile}),
        ),
      );
    });
  }

  test('the sequence: AU3 only for Married', () {
    expect(aboutUsSequence(null).length, 5);
    expect(aboutUsSequence(null), isNot(contains(AboutUsQuestion.married)));
    expect(aboutUsSequence(CoupleStage.married).length, 6);
  });

  // ---- Batch 4 additions (preflight F-3, batch-1 Minor 1, batch-3 carries,
  // every state visual, D2 attribution, the guidelines on every step).

  testWidgets(
    'F-3: AU6 on an empty About us offers "The day you got together" and '
    'saves the full date with the source in one write',
    (tester) async {
      final server = FakeCoupleProfileServer();
      var done = false;
      await pumpFlowScreen(
        tester,
        () => _flow(
          const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.anniversary,
          onDone: () => done = true,
        ),
        overrides: _overrides(server),
      );
      expect(find.text('No, thanks'), findsOneWidget);
      expect(find.text('The day you got together'), findsOneWidget);
      await tester.tap(find.text('The day you got together'));
      await tester.pumpAndSettle();
      expect(find.text('What day was it?'), findsOneWidget);
      expect(find.byKey(const ValueKey('about-us-anniversary-year')), findsOne);
      expect(
        find.byKey(const ValueKey('about-us-anniversary-month')),
        findsOne,
      );
      // A future date is refused here too, before anything is sent.
      await _choose(tester, 'about-us-anniversary-year', '2026');
      await _choose(tester, 'about-us-anniversary-month', 'December');
      await _choose(tester, 'about-us-anniversary-day', '1');
      await _continue(tester, 'Save');
      expect(find.text('That date is in the future.'), findsOneWidget);
      expect(server.count('update_couple_profile'), 0);
      await _choose(tester, 'about-us-anniversary-year', '2019');
      await _choose(tester, 'about-us-anniversary-month', 'October');
      await _choose(tester, 'about-us-anniversary-day', '14');
      await _continue(tester, 'Save');
      expect(server.count('update_couple_profile'), 1, reason: 'one write');
      expect(_lastPatch(server), {
        'together_since': '2019-10-14',
        'together_since_precision': 'day',
        'anniversary_source': 'together_since',
      });
      expect(done, isTrue);
    },
  );

  testWidgets('AU6: a year-only AU2 asks the month and day, not the year', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(
      profiles: {
        _rel: aboutUsJson(togetherSince: '2019-01-01', precision: 'year'),
      },
    );
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.anniversary,
      ),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('The day you got together'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('about-us-anniversary-year')),
      findsNothing,
    );
    await _choose(tester, 'about-us-anniversary-month', 'March');
    await _choose(tester, 'about-us-anniversary-day', '4');
    await _continue(tester, 'Save');
    expect(_lastPatch(server), {
      'together_since': '2019-03-04',
      'together_since_precision': 'day',
      'anniversary_source': 'together_since',
    });
  });

  testWidgets('30 February is refused and never rolls over (civilDate)', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer();
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.anniversary,
      ),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('The day you got together'));
    await tester.pumpAndSettle();
    await _choose(tester, 'about-us-anniversary-year', '2020');
    await _choose(tester, 'about-us-anniversary-month', 'February');
    await _chooseFar(tester, 'about-us-anniversary-day', '30');
    await _continue(tester, 'Save');
    expect(find.text('Check the day and month.'), findsOneWidget);
    expect(server.count('update_couple_profile'), 0, reason: 'not 1 March');
  });

  testWidgets('AU2: 29 February outside a leap year is refused', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer();
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.together,
      ),
      overrides: _overrides(server),
    );
    await _choose(tester, 'about-us-since-month', 'February');
    await _choose(tester, 'about-us-since-year', '2021');
    await tester.tap(find.text('Add the day'));
    await tester.pumpAndSettle();
    await _chooseFar(tester, 'about-us-since-day', '29');
    await _continue(tester, 'Save');
    expect(find.text('Check the day and month.'), findsOneWidget);
    expect(server.count('update_couple_profile'), 0);
  });

  testWidgets(
    'batch-1 Minor 1: ceremony 1 losing its day while the anniversary is on '
    'it asks for the day instead of sending a write the server refuses',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {
          _rel: aboutUsJson(
            stage: 'married',
            ceremonies: [
              {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
            ],
            anniversary: 'ceremony_1',
          ),
        },
      );
      await pumpFlowScreen(
        tester,
        () => _flow(
          const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.married,
        ),
        overrides: _overrides(server),
      );
      await _chooseFar(
        tester,
        'about-us-ceremony-0-day',
        'Not sure',
        delta: -100,
      );
      await _continue(tester, 'Save');
      expect(find.text(_stopTitle), findsOneWidget);
      expect(server.count('update_couple_profile'), 0);
      await tapInReach(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(_stopTitle), findsNothing);
      expect(server.count('update_couple_profile'), 0, reason: 'Cancel');
      expect(find.text('What year did you marry?'), findsOneWidget);
      // With the day back, the label change saves, no sheet.
      await _chooseFar(tester, 'about-us-ceremony-0-day', '15');
      await _continue(tester, 'Save');
      expect(_lastPatch(server), {
        'ceremonies': [
          {'year': 2004, 'month': 8, 'day': 15, 'label': 'church'},
        ],
      });
    },
  );

  testWidgets(
    'AU2 losing its day while the anniversary follows it asks for the day',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {
          _rel: aboutUsJson(
            togetherSince: '2019-10-14',
            precision: 'day',
            anniversary: 'together_since',
          ),
        },
      );
      await pumpFlowScreen(
        tester,
        () => _flow(
          const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.together,
        ),
        overrides: _overrides(server),
      );
      await tapInReach(tester, find.text('Not sure of the month'));
      await tester.pumpAndSettle();
      await _continue(tester, 'Save');
      expect(
        find.text(
          'Your anniversary reminder needs the full date. Add the day, or turn the reminder off first.',
        ),
        findsOneWidget,
      );
      expect(server.count('update_couple_profile'), 0);
    },
  );

  testWidgets(
    'AU1 counts "In your own words" as the server does (code points)',
    (tester) async {
      final server = FakeCoupleProfileServer();
      await pumpFlowScreen(
        tester,
        () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.stage),
        overrides: _overrides(server),
      );
      await tapInReach(tester, find.text('Something else'));
      await tester.pumpAndSettle();
      // 39 letters and one family emoji: 40 to the eye, 44 to char_length.
      final family = String.fromCharCodes([
        0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, //
      ]);
      await tester.enterText(find.byType(TextField), 'a' * 39 + family);
      await tester.pumpAndSettle();
      await _continue(tester, 'Save');
      final words = _lastPatch(server)!['stage_words'] as String;
      expect(words.runes.length, lessThanOrEqualTo(stageWordsMax));
      expect(stageWordsFit(words), isTrue);
    },
  );

  testWidgets('AU1: words the server would refuse are said, never sent', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(
      profiles: {
        'draft': aboutUsJson(draft: true, stage: 'other', stageWords: 'b' * 41),
      },
    );
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.stage),
      overrides: _overrides(server),
    );
    await _continue(tester, 'Save');
    expect(find.text('Use 40 characters or fewer.'), findsOneWidget);
    expect(server.count('update_my_couple_profile_draft'), 0);
  });

  testWidgets('loading, then a load failure in words with Try again', (
    tester,
  ) async {
    final server =
        FakeCoupleProfileServer()..failAlways = TimeoutException('offline');
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.shared(_rel)),
      overrides: _overrides(server),
    );
    expect(
      find.text(
        "We couldn't load About us. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    server.failAlways = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(
      find.text('How would you describe where you two are?'),
      findsOneWidget,
    );
  });

  testWidgets('read-only: said with its end date, and nothing to answer', (
    tester,
  ) async {
    var done = false;
    final server = FakeCoupleProfileServer(
      profiles: {
        _rel: aboutUsJson(
          readOnly: true,
          readUntil: '2026-12-01T10:00:00+00:00',
        ),
      },
    );
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.anniversary,
        onDone: () => done = true,
      ),
      overrides: _overrides(server),
    );
    expect(find.text("About us can't be changed right now."), findsOneWidget);
    expect(find.textContaining('You can read this until '), findsOneWidget);
    expect(find.text('The day you got together'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(server.count('update_couple_profile'), 0);
  });

  testWidgets('offline in the flow: the next question says it is kept here', (
    tester,
  ) async {
    final server =
        FakeCoupleProfileServer()..failUpdates = TimeoutException('offline');
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.draft()),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('Dating'));
    await tester.pumpAndSettle();
    await _continue(tester);
    expect(find.text('When did you two get together?'), findsOneWidget);
    expect(
      find.text(
        "Saved on this phone. It will be shared when you're back online.",
      ),
      findsOneWidget,
    );
  });

  test('D2: "Changed by Yaw - Thu, 12 Nov", "you", "your partner"', () {
    final loc = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 11, 13);
    expect(
      changedByText(
        loc,
        FieldChange(
          byMe: false,
          byFirstName: 'Yaw',
          at: DateTime(2026, 11, 12, 9),
        ),
        now,
      ),
      'Changed by Yaw - Thu, 12 Nov',
    );
    expect(
      changedByText(
        loc,
        FieldChange(
          byMe: true,
          byFirstName: 'Kofi',
          at: DateTime(2026, 11, 12, 9),
        ),
        now,
      ),
      'Changed by you - Thu, 12 Nov',
    );
    expect(
      changedByText(
        loc,
        FieldChange(byMe: false, at: DateTime(2025, 3, 4)),
        now,
      ),
      'Changed by your partner - Tuesday, March 4, 2025',
    );
  });

  testWidgets('the guidelines hold on every step, AU6\'s date and read-only', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final married = aboutUsJson(
      draft: true,
      stage: 'married',
      togetherSince: '2019-10-01',
      precision: 'month',
      ceremonies: [
        {'year': 1999, 'label': 'customary'},
      ],
    );
    for (final question in AboutUsQuestion.values) {
      await pumpFlowScreen(
        tester,
        () => _flow(const AboutUsTarget.draft(), only: question),
        overrides: _overrides(
          FakeCoupleProfileServer(profiles: {'draft': married}),
        ),
      );
      await expectFlowGuidelines(tester);
    }
    await pumpFlowScreen(
      tester,
      () =>
          _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.anniversary),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await tester.tap(find.text('The day you got together'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.shared(_rel)),
      overrides: _overrides(
        FakeCoupleProfileServer(
          profiles: {
            _rel: aboutUsJson(
              readOnly: true,
              readUntil: '2026-12-01T10:00:00+00:00',
            ),
          },
        ),
      ),
    );
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  testWidgets('goldens: about_us_au6_date (F-3, the full date asked)', (
    tester,
  ) async {
    await expectFlowGoldens(
      tester,
      'about_us_au6_date',
      () =>
          _flow(const AboutUsTarget.draft(), only: AboutUsQuestion.anniversary),
      overrides: _overrides(FakeCoupleProfileServer()),
      before: (tester) async {
        await tester.tap(find.text('The day you got together'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets(
    'batch-3 re-review carry: with couple_profile off no step can be reached '
    '(a deep link included): nothing is fetched or shown, and it closes',
    (tester) async {
      for (final question in [null, ...AboutUsQuestion.values]) {
        final server = FakeCoupleProfileServer();
        var done = 0;
        await pumpFlowScreen(
          tester,
          () => _flow(
            const AboutUsTarget.shared(_rel),
            only: question,
            onDone: () => done++,
          ),
          overrides: _overrides(server, enabled: false),
        );
        expect(server.calls, isEmpty, reason: '$question: nothing fetched');
        expect(find.byType(AboutUsChoice), findsNothing);
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        expect(find.text('About us'), findsNothing);
        expect(done, 1, reason: '$question: closed once');
      }
    },
  );

  testWidgets('a refusal at load is said and offers Close, not Try again', (
    tester,
  ) async {
    var done = false;
    final server =
        FakeCoupleProfileServer()
          ..failAlways = FakeCoupleProfileServer.refusal(
            'couple_profile:not_found',
          );
    await pumpFlowScreen(
      tester,
      () => _flow(const AboutUsTarget.shared(_rel), onDone: () => done = true),
      overrides: _overrides(server),
    );
    expect(find.text("About us can't be changed right now."), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  // ---- Fix round 1 (batch-4-review.md I-1, M-1..M-4; ruling "leaving
  // Married": never a silent stop of the anniversary reminder).

  Map<String, dynamic> twoCeremonies({
    String anniversary = 'ceremony_2',
    String? togetherSince,
    String? precision,
  }) => aboutUsJson(
    stage: 'married',
    togetherSince: togetherSince,
    precision: precision,
    ceremonies: [
      {'year': 1999, 'label': 'customary'},
      {'year': 2004, 'month': 8, 'day': 14, 'label': 'church'},
    ],
    anniversary: anniversary,
  );

  testWidgets('I-1: removing the ceremony the anniversary is on asks first; '
      '"Turn it off" saves once', (tester) async {
    final server = FakeCoupleProfileServer(profiles: {_rel: twoCeremonies()});
    var done = false;
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.married,
        onDone: () => done = true,
      ),
      overrides: _overrides(server),
    );
    await tester.ensureVisible(find.text('Remove this ceremony'));
    await tester.tap(find.text('Remove this ceremony'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    expect(find.text(_stopTitle), findsOneWidget);
    expect(server.count('update_couple_profile'), 0);
    expect(find.text('The day you got together'), findsOneWidget);
    await tapInReach(tester, find.text('Turn it off'));
    await tester.pumpAndSettle();
    expect(server.count('update_couple_profile'), 1);
    expect(_lastPatch(server), {
      'ceremonies': [
        {'year': 1999, 'label': 'customary'},
      ],
      'anniversary_source': 'off',
    });
    expect(done, isTrue);
  });

  testWidgets(
    'I-1: "The day you got together" moves the reminder in the same write',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {
          _rel: twoCeremonies(togetherSince: '2019-10-14', precision: 'day'),
        },
      );
      await pumpFlowScreen(
        tester,
        () => _flow(
          const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.married,
        ),
        overrides: _overrides(server),
      );
      await tester.ensureVisible(find.text('Remove this ceremony'));
      await tester.tap(find.text('Remove this ceremony'));
      await tester.pumpAndSettle();
      await _continue(tester, 'Save');
      await tapInReach(tester, find.text('The day you got together'));
      await tester.pumpAndSettle();
      expect(server.count('update_couple_profile'), 1);
      expect(_lastPatch(server), {
        'ceremonies': [
          {'year': 1999, 'label': 'customary'},
        ],
        'anniversary_source': 'together_since',
      });
    },
  );

  testWidgets(
    'I-1: a ceremony losing its day, AU2 unanswered: the sheet asks the '
    'whole date and saves it with the reminder in one write',
    (tester) async {
      final server = FakeCoupleProfileServer(profiles: {_rel: twoCeremonies()});
      await pumpFlowScreen(
        tester,
        () => _flow(
          const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.married,
        ),
        overrides: _overrides(server),
      );
      await _chooseFar(
        tester,
        'about-us-ceremony-1-day',
        'Not sure',
        delta: -100,
      );
      await _continue(tester, 'Save');
      expect(find.text(_stopTitle), findsOneWidget);
      await tapInReach(tester, find.text('The day you got together'));
      await tester.pumpAndSettle();
      expect(server.count('update_couple_profile'), 0, reason: 'no date yet');
      expect(find.text('What day was it?'), findsOneWidget);
      await _choose(tester, 'about-us-stop-year', '2019');
      await _choose(tester, 'about-us-stop-month', 'October');
      await _choose(tester, 'about-us-stop-day', '14');
      await tapInReach(tester, find.text('Save').last);
      await tester.pumpAndSettle();
      expect(server.count('update_couple_profile'), 1);
      expect(_lastPatch(server), {
        'ceremonies': [
          {'year': 1999, 'label': 'customary'},
          {'year': 2004, 'month': 8, 'label': 'church'},
        ],
        'together_since': '2019-10-14',
        'together_since_precision': 'day',
        'anniversary_source': 'together_since',
      });
    },
  );

  testWidgets(
    'ruling: leaving Married with the anniversary on a ceremony asks first',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {_rel: twoCeremonies(anniversary: 'ceremony_1')},
      );
      await pumpFlowScreen(
        tester,
        () => _flow(
          const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.stage,
        ),
        overrides: _overrides(server),
      );
      await tester.tap(find.text('Dating'));
      await tester.pumpAndSettle();
      await _continue(tester, 'Save');
      expect(find.text(_stopTitle), findsOneWidget);
      await tapInReach(tester, find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.count('update_couple_profile'), 0);
      expect(
        find.text('How would you describe where you two are?'),
        findsOneWidget,
      );
      await _continue(tester, 'Save');
      await tapInReach(tester, find.text('Turn it off'));
      await tester.pumpAndSettle();
      expect(server.count('update_couple_profile'), 1);
      expect(_lastPatch(server), {
        'stage': 'dating',
        'stage_words': null,
        'anniversary_source': 'off',
      });
    },
  );

  testWidgets('leaving Married with the anniversary off asks nothing', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(
      profiles: {_rel: twoCeremonies(anniversary: 'off')},
    );
    await pumpFlowScreen(
      tester,
      () =>
          _flow(const AboutUsTarget.shared(_rel), only: AboutUsQuestion.stage),
      overrides: _overrides(server),
    );
    await tester.tap(find.text('Dating'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    expect(find.text(_stopTitle), findsNothing);
    expect(_lastPatch(server), {'stage': 'dating', 'stage_words': null});
  });

  testWidgets(
    'M-1: on 31 December a stored next-year date shows, with no assert and '
    'no blank, and an untouched answer saves nothing',
    (tester) async {
      final server = FakeCoupleProfileServer(
        profiles: {
          _rel: aboutUsJson(
            togetherSince: '2027-01-01',
            precision: 'day',
            stage: 'married',
            ceremonies: [
              {'year': 2027, 'month': 1, 'day': 1},
            ],
          ),
        },
      );
      for (final question in [
        AboutUsQuestion.together,
        AboutUsQuestion.married,
      ]) {
        var done = false;
        await pumpFlowScreen(
          tester,
          () => AboutUsQuestionFlow(
            target: const AboutUsTarget.shared(_rel),
            only: question,
            now: () => DateTime(2026, 12, 31, 23),
            onDone: () => done = true,
          ),
          overrides: _overrides(server),
        );
        expect(tester.takeException(), isNull, reason: '$question');
        expect(find.text('2027'), findsOneWidget, reason: '$question');
        await _continue(tester, 'Save');
        expect(find.text('That date is in the future.'), findsNothing);
        expect(done, isTrue, reason: '$question');
      }
      expect(server.count('update_couple_profile'), 0);
    },
  );

  testWidgets(
    'M-1: a stored year past the list (a phone clock behind) is still listed',
    (tester) async {
      await pumpFlowScreen(
        tester,
        () => AboutUsQuestionFlow(
          target: const AboutUsTarget.shared(_rel),
          only: AboutUsQuestion.together,
          now: () => DateTime(2026, 6, 1),
          onDone: () {},
        ),
        overrides: _overrides(
          FakeCoupleProfileServer(
            profiles: {
              _rel: aboutUsJson(
                togetherSince: '2028-03-01',
                precision: 'month',
              ),
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2028'), findsOneWidget);
    },
  );

  testWidgets('M-1: the year list reaches the server\'s UTC today + 1', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => AboutUsQuestionFlow(
        target: const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.together,
        now: () => DateTime(2026, 12, 31, 23),
        onDone: () {},
      ),
      overrides: _overrides(FakeCoupleProfileServer()),
    );
    await tester.tap(find.byKey(const ValueKey('about-us-since-year')));
    await tester.pumpAndSettle();
    expect(find.text('2027').hitTestable(), findsOneWidget);
  });

  testWidgets('M-3: AU2\'s day can be taken away again', (tester) async {
    final server = FakeCoupleProfileServer(
      profiles: {
        _rel: aboutUsJson(togetherSince: '2019-10-14', precision: 'day'),
      },
    );
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.together,
      ),
      overrides: _overrides(server),
    );
    await _chooseFar(tester, 'about-us-since-day', 'Not sure', delta: -100);
    await _continue(tester, 'Save');
    expect(_lastPatch(server), {
      'together_since': '2019-10-01',
      'together_since_precision': 'month',
    });
  });

  for (final (name, question, profile) in [
    (
      'about_us_au4',
      AboutUsQuestion.living,
      aboutUsJson(living: 'apart_nearby'),
    ),
    (
      'about_us_read_only',
      null,
      // Batch 5 (re-review N-1): local noon, so the golden's date is the
      // same in every zone (UTC+14 and UTC-11 included).
      aboutUsJson(
        readOnly: true,
        readUntil: DateTime(2026, 12, 1, 12).toUtc().toIso8601String(),
      ),
    ),
  ]) {
    testWidgets('goldens: $name (M-4)', (tester) async {
      await expectFlowGoldens(
        tester,
        name,
        () => _flow(const AboutUsTarget.shared(_rel), only: question),
        overrides: _overrides(
          FakeCoupleProfileServer(profiles: {_rel: profile}),
        ),
      );
    });
  }

  testWidgets('the guidelines hold on the reminder-stop sheet', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      () => _flow(
        const AboutUsTarget.shared(_rel),
        only: AboutUsQuestion.married,
      ),
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: twoCeremonies()}),
      ),
    );
    await tester.ensureVisible(find.text('Remove this ceremony'));
    await tester.tap(find.text('Remove this ceremony'));
    await tester.pumpAndSettle();
    await _continue(tester, 'Save');
    await expectFlowGuidelines(tester);
    await tapInReach(tester, find.text('The day you got together'));
    await tester.pumpAndSettle();
    await expectFlowGuidelines(tester);
    handle.dispose();
  });
}
