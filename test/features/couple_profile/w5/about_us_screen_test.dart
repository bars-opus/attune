// Spec 1 W5 (§3.8 About us screen, D2, §2.3): one row per question, the
// answer in words (dates through MyDateFormat, never a count), "Changed by
// {first name or 'you'} - {date}" under each answered row, the couple's
// name as the title (else "About us"), read-only with its end date while
// paused or in the window, a row tap asks that question again; goldens and
// guidelines.
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_question_flow.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart'
    show coupleProfileEnabledProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_couple_profile.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';

const _rel = 'rel-screen';
final _enDash = String.fromCharCode(0x2013);
final _middleDot = String.fromCharCode(0xB7);
final _now = DateTime(2026, 11, 20, 10);

/// Batch 5 (batch-4 re-review N-1): an instant at local noon, so the day
/// shown is the same in every zone (UTC+14 and UTC-11 included).
String _localNoon(int year, int month, int day) =>
    DateTime(year, month, day, 12).toUtc().toIso8601String();

Map<String, dynamic> _answered({bool readOnly = false}) => aboutUsJson(
  readOnly: readOnly,
  readUntil: readOnly ? _localNoon(2026, 12, 1) : null,
  togetherSince: '2024-10-01',
  precision: 'month',
  stage: 'married',
  ceremonies: [
    {'year': 1999, 'label': 'customary'},
    {'year': 2004, 'month': 8, 'day': 14},
  ],
  living: 'apart_nearby',
  children: 'yes',
  bands: ['13to17', '18plus'],
  anniversary: 'together_since',
  changes: {
    'together_since': {
      'changed_by_me': false,
      'changed_by_first_name': 'Yaw',
      'changed_at': _localNoon(2026, 11, 12),
    },
    'stage': {'changed_by_me': true, 'changed_at': _localNoon(2025, 3, 4)},
    'living': {'changed_by_me': false, 'changed_at': _localNoon(2026, 11, 1)},
  },
);

List<Override> _overrides(FakeCoupleProfileServer server, {String? name}) => [
  // Batch 4's flag gate: every About us host reads couple_profile.
  coupleProfileEnabledProvider.overrideWithValue(true),
  coupleProfileRpcProvider.overrideWithValue(server.rpc),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-screen'))),
  togetherChangeSignalProvider.overrideWith((ref, id) => const Stream.empty()),
  coupleNameProvider.overrideWith((ref, id) async => name),
];

Widget _screen({AboutUsTarget target = const AboutUsTarget.shared(_rel)}) =>
    AboutUsScreen(target: target, onClose: () {}, now: _now);

void main() {
  testWidgets('every answer in words, attributed, never a count', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
        name: 'The Mensahs',
      ),
      size: const Size(390, 1400),
    );
    expect(find.text('The Mensahs'), findsOneWidget, reason: 'the chat name');
    expect(find.text('October 2024'), findsOneWidget);
    expect(find.text('Married'), findsOneWidget);
    expect(find.text('Customary, 1999\n2004'), findsOneWidget);
    expect(find.text('Apart, nearby'), findsOneWidget);
    expect(find.text('Yes (13${_enDash}17, 18+)'), findsOneWidget);
    expect(find.text('The day you got together'), findsOneWidget);
    // D2: a spaced dash, the short date this year, the full one before.
    expect(find.text('Changed by Yaw - Thu, 12 Nov'), findsOneWidget);
    expect(
      find.text('Changed by you - Tuesday, March 4, 2025'),
      findsOneWidget,
    );
    expect(find.text('Changed by your partner - Sun, 1 Nov'), findsOneWidget);
    expect(find.textContaining(_middleDot), findsNothing);
    expect(
      find.textContaining(RegExp(r'\d+ (years?|months?|days?)')),
      findsNothing,
    );
    expect(
      find.text(
        "Either of you can change these. It's never used to score or type you.",
      ),
      findsOneWidget,
    );
    expect(
      find.text('You can read this until Tuesday, December 1, 2026.'),
      findsNothing,
    );
  });

  testWidgets('without a chat name the title is About us; empty rows say so', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(FakeCoupleProfileServer()),
      size: const Size(390, 1400),
    );
    expect(find.text('About us'), findsOneWidget);
    expect(find.text('Not answered yet'), findsNWidgets(4));
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Answer a few questions'), findsOneWidget);
    expect(find.textContaining('Changed by'), findsNothing);
  });

  testWidgets('read-only: its end date, and no row opens a question', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered(readOnly: true)}),
      ),
      size: const Size(390, 1400),
    );
    expect(
      find.text('You can read this until Tuesday, December 1, 2026.'),
      findsOneWidget,
    );
    await tapInReach(tester, find.text('Apart, nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Where do you two live?'), findsNothing);
    // Batch 5: nothing is opened at all (not even the flow's read-only
    // frame), and no row is offered as a button.
    expect(find.byType(AboutUsQuestionFlow), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  // Fix round 1 (review I-1): a screen reader can activate a row (one
  // labelled node with a tap action); a read-only row offers none.
  testWidgets('screen readers: a row is one node with a tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
      ),
      size: const Size(390, 1400),
    );
    final row = find.bySemanticsLabel(RegExp('^Where you live'));
    expect(row, findsOneWidget);
    expect(
      tester
          .getSemantics(row)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.semantics.tap(find.semantics.byLabel(RegExp('^Where you live')));
    await tester.pumpAndSettle();
    expect(find.text('Where do you two live?'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('screen readers: a read-only row offers no tap action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered(readOnly: true)}),
      ),
      size: const Size(390, 1400),
    );
    final row = find.bySemanticsLabel(RegExp('^Where you live'));
    expect(row, findsOneWidget);
    expect(
      tester
          .getSemantics(row)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('a row asks its question again, and the answer comes back', (
    tester,
  ) async {
    final server = FakeCoupleProfileServer(profiles: {_rel: _answered()});
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(server),
      size: const Size(390, 1400),
    );
    await tester.tap(find.text('Apart, nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Where do you two live?'), findsOneWidget);
    await tester.tap(find.text('Long distance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Long distance'), findsOneWidget);
    expect(find.textContaining('Changed by you'), findsWidgets);
  });

  testWidgets('a failed load says so and tries again', (tester) async {
    final server =
        FakeCoupleProfileServer()
          ..failNext = FakeCoupleProfileServer.refusal('boom');
    await pumpFlowScreen(tester, _screen, overrides: _overrides(server));
    expect(
      find.text(
        "We couldn't load About us. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    // Fix round 1 (review M-6): the error state meets the guidelines too.
    final handle = tester.ensureSemantics();
    await expectFlowGuidelines(tester);
    handle.dispose();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Not answered yet'), findsWidgets);
  });

  // Fix round 1 (review M-3): a refusal (archived, sealed, the draft after
  // linking, another couple's id) is not the connection: no Try again.
  testWidgets('a refused load says About us is unavailable, with Close', (
    tester,
  ) async {
    var closed = false;
    final server =
        FakeCoupleProfileServer()
          ..failAlways = FakeCoupleProfileServer.refusal(
            'couple_profile:not_found',
          );
    await pumpFlowScreen(
      tester,
      () => AboutUsScreen(
        target: const AboutUsTarget.shared(_rel),
        onClose: () => closed = true,
        now: _now,
      ),
      overrides: _overrides(server),
    );
    expect(find.text("About us can't be changed right now."), findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    final handle = tester.ensureSemantics();
    await expectFlowGuidelines(tester);
    handle.dispose();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('the guidelines hold', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFlowScreen(
      tester,
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
      ),
    );
    await expectFlowGuidelines(tester);
    handle.dispose();
  });

  testWidgets('goldens: about_us_screen', (tester) async {
    await expectFlowGoldens(
      tester,
      'about_us_screen',
      _screen,
      overrides: _overrides(
        FakeCoupleProfileServer(profiles: {_rel: _answered()}),
        name: 'The Mensahs',
      ),
    );
  });
}
