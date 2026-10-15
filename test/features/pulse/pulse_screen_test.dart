import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/pulse/data/models/pulse_score.dart';
import 'package:attune/features/pulse/presentation/screens/pulse_screen.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show currentPulseScoreProvider, currentRelationshipIdProvider, pulseHistoryProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show bothPartnersSharedProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The "Relationship Center" panel (score/delta/confidence tiles, weekly
/// check-in row, attachment-quiz row, relationship-tips placeholder)
/// moved here from the old ChatIdentityCard — it now lives inside
/// PulseScreen itself, right after the Score card, rather than in a
/// header shared across every PulseTab tab.
void main() {
  const relId = 'rel-1';

  // PulseScreen requires a NestedScrollView ancestor (its own
  // SliverOverlapInjector, the same wiring PulseTab's real NestedScrollView
  // supplies) — a bare Scaffold throws "no absorbed extent to inject".
  // Wrapped in a real NestedScrollView with a trivial header sliver rather
  // than reaching for PulseTab itself, so this file only needs the
  // providers PulseScreen actually touches, not chat/reminders/timeline
  // ones PulseTab's own header would also require.
  Widget buildHarness(ProviderContainer container) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                    context,
                  ),
                  sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ],
              body: const PulseScreen(),
            ),
          ),
        ),
        GoRoute(
          path: '/weeklyCheckin',
          name: 'weeklyCheckin',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('weekly checkin'))),
        ),
        GoRoute(
          path: '/quizEntry',
          name: 'quizEntry',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('quiz entry'))),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  PulseScore pulseScore({
    required int overall,
    int? overallDelta,
    String confidence = 'medium',
  }) {
    return PulseScore(
      id: 'pulse-1',
      relationshipId: relId,
      weekEnding: DateTime(2026, 1, 4),
      computedAt: DateTime(2026, 1, 4),
      overallScore: overall,
      communication: 70,
      connection: 70,
      conflictHealth: 70,
      alignment: 70,
      emotionalSafety: 70,
      dataConfidence: confidence,
      deltaVsPrevious: overallDelta == null ? null : {'overall': overallDelta},
    );
  }

  Future<ProviderContainer> pumpWithPulse(
    WidgetTester tester, {
    PulseScore? pulse,
    bool bothSharedQuiz = false,
    String? coupleName,
  }) async {
    final container = ProviderContainer(
      overrides: [
        currentPulseScoreProvider.overrideWith((ref) async => pulse),
        pulseHistoryProvider.overrideWith((ref) async => const []),
        bothPartnersSharedProvider.overrideWith((ref) async => bothSharedQuiz),
        currentRelationshipIdProvider.overrideWith((ref) async => 'r1'),
        coupleNameProvider.overrideWith((ref, id) async => coupleName),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildHarness(container));
    await tester.pump();
    await tester.pump();
    return container;
  }

  // flutter_test's default surface is 800x600 — too short to hit-test the
  // Weekly check-in / Attachment styles / Relationship tips rows, which
  // sit below the Score card. Scrolls the finder into view rather than
  // trying a taller physical surface (which, combined with this file's
  // ScreenUtilInit designSize, pushed an unrelated pre-existing
  // TrendChart overflow into view instead of fixing the hit-test issue).
  // flutter_test's default surface is 800x600 — too short to hit-test the
  // Weekly check-in / Attachment styles / Relationship tips rows, which
  // sit below the Score card. Wider AND taller than a real phone: the
  // Score card's VisualisationSwitcher and TrendChart both overflow
  // horizontally at real-phone widths once real pulse data forces them
  // to actually render (a pre-existing bug that pulse_tab_test.dart never
  // exercises, since its own harness always overrides the score to null,
  // hitting the no-data empty-state branch before either widget builds).
  void useTallPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('relationship tips are for the couple, by their chosen name', (tester) async {
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72), coupleName: 'The Harolds');
    await tester.pumpAndSettle();
    expect(find.text('Ideas curated for The Harolds', skipOffstage: false), findsOneWidget);
  });

  testWidgets('relationship tips say couples until a name is chosen', (tester) async {
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));
    await tester.pumpAndSettle();
    expect(find.text('Ideas curated for couples', skipOffstage: false), findsOneWidget);
  });

  testWidgets('renders the Relationship Center panel heading', (
    tester,
  ) async {
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

    expect(find.text('Relationship Center'), findsOneWidget);
    // 'Weekly check-in' also appears as CheckinBanner's own title further
    // down the screen — findsWidgets (at least one), not findsOneWidget.
    expect(find.text('Weekly check-in'), findsWidgets);
    expect(find.text('Relationship tips'), findsOneWidget);
  });

  testWidgets('shows the real overall score, signed weekly delta, and '
      'confidence label', (tester) async {
    await pumpWithPulse(
      tester,
      pulse: pulseScore(overall: 72, overallDelta: 3, confidence: 'high'),
    );

    expect(find.text('72'), findsOneWidget);
    // Signed so a rise reads unambiguously as movement, not a raw score.
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Confidence'), findsOneWidget);
  });

  testWidgets('renders a negative delta with its sign intact', (
    tester,
  ) async {
    await pumpWithPulse(tester, pulse: pulseScore(overall: 61, overallDelta: -4));

    expect(find.text('-4'), findsOneWidget);
  });

  testWidgets('a first-ever score (no previous week) shows a placeholder '
      'delta, never a misleading "0"', (tester) async {
    await pumpWithPulse(
      tester,
      // deltaVsPrevious null — compute-pulse omits it entirely when there
      // is no prior week to diff against.
      pulse: pulseScore(overall: 55),
    );

    expect(find.text('55'), findsOneWidget);
    // The delta placeholder is the em-dash, not a misleading "0" — scoped
    // to "This week"'s own tile since the score ring/number visualisation
    // elsewhere on the screen legitimately renders other "0"s (e.g. an
    // animation start frame) unrelated to the delta this test guards.
    final thisWeekTile = find.ancestor(
      of: find.text('This week'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: thisWeekTile.first, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: thisWeekTile.first, matching: find.text('0')),
      findsNothing,
    );
  });

  testWidgets('confidence "none" renders as "Early", not "None"', (
    tester,
  ) async {
    await pumpWithPulse(
      tester,
      pulse: pulseScore(overall: 40, confidence: 'none'),
    );

    // PULSE.md §7's own copy for this state is encouraging ("keep using
    // Attune"); a bare "None" reads as the couple's failure.
    expect(find.text('Early'), findsOneWidget);
    expect(find.text('None'), findsNothing);
  });

  testWidgets('never renders a streak tile — PULSE.md §6 bans streaks '
      'outright as a permanent ATTUNE_SOUL.md constraint', (tester) async {
    await pumpWithPulse(
      tester,
      pulse: pulseScore(overall: 72, overallDelta: 3),
    );

    expect(find.textContaining('streak'), findsNothing);
    expect(find.textContaining('Streak'), findsNothing);
    // The other two originally-dummy tiles are equally forbidden:
    // response rate is chat-derived per-partner attribution (chat→Pulse
    // spec Privacy section + permanent constraint #2).
    expect(find.textContaining('Response rate'), findsNothing);
  });

  testWidgets('the attachment-quiz row reflects whether BOTH partners '
      'have shared', (tester) async {
    await pumpWithPulse(
      tester,
      pulse: pulseScore(overall: 72),
      bothSharedQuiz: true,
    );

    expect(find.text('Attachment styles'), findsOneWidget);
    expect(find.text('You have both shared your results'), findsOneWidget);
  });

  testWidgets('the attachment-quiz row nudges when they have not both '
      'shared', (tester) async {
    await pumpWithPulse(
      tester,
      pulse: pulseScore(overall: 72),
      bothSharedQuiz: false,
    );

    expect(
      find.text('Take it together to strengthen your Pulse'),
      findsOneWidget,
    );
  });

  testWidgets('tapping Weekly check-in opens the real check-in route', (
    tester,
  ) async {
    useTallPhoneSurface(tester);
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    // 'Weekly check-in' also appears as CheckinBanner's own title further
    // down the screen — tap the Relationship Center panel's row (an
    // InfoRowWidget) specifically, not that ambiguous bare text match.
    await tester.tap(
      find.ancestor(
        of: find.text('Weekly check-in'),
        matching: find.byType(InfoRowWidget),
      ).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('weekly checkin'), findsOneWidget);
  });

  testWidgets('tapping Attachment styles opens the real quiz route', (
    tester,
  ) async {
    useTallPhoneSurface(tester);
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attachment styles'));
    await tester.pumpAndSettle();

    expect(find.text('quiz entry'), findsOneWidget);
  });

  testWidgets('Relationship tips is present but NOT tappable — it has no '
      'backing feature yet and must not route anywhere', (tester) async {
    useTallPhoneSurface(tester);
    await pumpWithPulse(tester, pulse: pulseScore(overall: 72));

    expect(find.text('Relationship tips'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relationship tips'));
    await tester.pumpAndSettle();

    // Still on the screen — no navigation happened.
    expect(find.text('Relationship tips'), findsOneWidget);
    expect(find.text('weekly checkin'), findsNothing);
    expect(find.text('quiz entry'), findsNothing);
  });

  testWidgets('a couple with no computed Pulse yet shows the no-data '
      'empty state instead of the Relationship Center panel', (tester) async {
    // PulseScreen's own data branch returns _buildNoDataState() early
    // when pulse is null, before reaching the Relationship Center panel
    // (or the Score/Dimensions cards) at all — a brand-new relationship
    // sees the empty state, not placeholder tiles.
    await pumpWithPulse(tester, pulse: null);

    expect(find.text('No pulse score yet'), findsOneWidget);
    expect(find.text('Relationship Center'), findsNothing);
  });
}
