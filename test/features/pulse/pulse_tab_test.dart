import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/pulse/presentation/screens/pulse_tab.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    as pulse_providers;
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline_providers;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/chat_test_harness.dart';

/// Overrides RemindersListNotifier's build() — the real one calls
/// Supabase.instance.client synchronously, which throws with no app-level
/// Supabase.initialize() in a test host. remindersListProvider's
/// `AsyncNotifierProvider<RemindersListNotifier, ...>` type requires the
/// override factory to return exactly RemindersListNotifier, so this
/// extends the real class rather than AsyncNotifier directly.
class _FakeRemindersListNotifier extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  // Full end-to-end exercise of the REAL PulseTab widget — every provider
  // PulseScreen/TimelineScreen/PulseIdentityRow touch during build is
  // overridden to a harmless value so this reaches actual layout without a
  // live Supabase client, while still using PulseTab's real
  // NestedScrollView + SliverOverlapAbsorber/Injector wiring end to end.
  // Uses a REAL (non-null) conversation via FakeChatRepository — chat's own
  // test harness — so PulseIdentityRow and ChatSettingsStaticRows both
  // render their actual content rather than PulseTab's "unavailable"
  // fallback, which is what a null conversation would hit instead.
  Widget buildHarness() {
    final repo = FakeChatRepository(currentUserId: userId);
    return ProviderScope(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWith((ref) => testUser(userId)),
        primaryConversationProvider.overrideWith(
          (ref) async => activeConversation(relId),
        ),
        pulse_providers.currentPulseScoreProvider.overrideWith(
          (ref) async => null,
        ),
        pulse_providers.pulseHistoryProvider.overrideWith((ref) async => []),
        timeline_providers.currentUserIdProvider.overrideWithValue(null),
        timeline_providers.currentRelationshipIdProvider.overrideWith(
          (ref) async => relId,
        ),
        timeline_providers.timelineEventsProvider.overrideWith(
          (ref, month) async => [],
        ),
        remindersListProvider.overrideWith(_FakeRemindersListNotifier.new),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        child: const MaterialApp(home: PulseTab()),
      ),
    );
  }

  // Scoped to the TabBar specifically — 'Pulse'/'Settings' also appear as
  // plain body text inside PulseScreen/ChatSettingsStaticRows, so an
  // unscoped find.text ambiguously matches both the tab label and content.
  Finder tabLabel(String label) =>
      find.descendant(of: find.byType(TabBar), matching: find.text(label));

  // flutter_test's default surface is 800x600 — shorter than any real
  // phone, and too short for the tab bar's content to lay out with room
  // to hit-test it. Use a realistic tall portrait surface so taps on the
  // tab bar land.
  void useTallPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('builds both tabs with no layout exceptions '
      '(guards the NestedScrollView/SliverOverlapAbsorber wiring compiling '
      'and laying out correctly end to end) — Timeline is commented out, '
      'not a third tab', (tester) async {
    useTallPhoneSurface(tester);
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tabLabel('Settings'), findsOneWidget);
    expect(tabLabel('Pulse'), findsOneWidget);
    expect(tabLabel('Timeline'), findsNothing);
    // The identity row now lives inside the Settings tab (not a shared
    // header above both tabs) — confirms the default (Pulse) tab renders
    // its own real content, not the identity row.
    expect(find.text('Partner'), findsNothing); // activeConversation's name
  });

  testWidgets(
    'the two tabs are centered and split the bar evenly, matching '
    'ReflectionJournalScreen\'s own TabsWithContent(scrollable: false) '
    'look — not left-aligned, content-sized tabs',
    (tester) async {
      useTallPhoneSurface(tester);
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(
        tabBar.isScrollable,
        isFalse,
        reason: 'scrollable tabs are left-aligned and content-sized, not '
            'centered and evenly split',
      );

      // Each tab's own rect should be exactly half the TabBar's width and
      // start where the other one ends — the concrete shape
      // "half of each screen like Expanded" describes. Compares the tabs'
      // own containing Tab widgets, not just their text labels (a short
      // label sits centered within a much wider tab), so this reads the
      // actual half-and-half split rather than incidental text position.
      final barRect = tester.getRect(find.byType(TabBar));
      final pulseTabRect = tester.getRect(
        find.ancestor(of: tabLabel('Pulse'), matching: find.byType(Tab)).first,
      );
      final settingsTabRect = tester.getRect(
        find.ancestor(
          of: tabLabel('Settings'),
          matching: find.byType(Tab),
        ).first,
      );

      expect(pulseTabRect.left, closeTo(barRect.left, 1));
      expect(settingsTabRect.right, closeTo(barRect.right, 1));
      expect(pulseTabRect.right, closeTo(settingsTabRect.left, 1));
      expect(
        pulseTabRect.width,
        closeTo(settingsTabRect.width, 1),
        reason: 'each tab should take an equal half of the bar',
      );
    },
  );

  testWidgets(
    'scrolling the Pulse tab (which owns its own CustomScrollView) moves '
    'the tab bar above it too, instead of only scrolling internally',
    (tester) async {
      useTallPhoneSurface(tester);
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      await tester.tap(tabLabel('Pulse'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final tabBarBefore = tester.getTopLeft(find.byType(TabBar));

      // Drag from inside the TabBarView itself (Pulse's own CustomScrollView
      // fills it) rather than a specific text label — a label positioned
      // below the small test viewport can't be hit-tested at all, where the
      // TabBarView's own body is always large and on-screen.
      //
      // A small offset, not -300: the header above the tab bar shrank once
      // the identity card moved out of it, so a large drag now scrolls the
      // tab bar fully off-screen (0 widgets found) instead of just moving
      // it — this only needs to prove movement, not scroll it away.
      await tester.drag(find.byType(TabBarView), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Under the old TabsWithContent(useNestedScrollMode) bug, this drag
      // would be consumed entirely by PulseScreen's own inner
      // CustomScrollView and the outer position (and therefore the tab
      // bar's own position) would not move at all.
      final tabBarAfter = tester.getTopLeft(find.byType(TabBar));
      expect(tabBarAfter.dy, isNot(tabBarBefore.dy));
    },
  );

  testWidgets('scrolling the Settings tab does not throw a RenderFlex '
      'overflow, and it too moves the tab bar above it', (tester) async {
    useTallPhoneSurface(tester);
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();

    // Settings is no longer the initial tab: 31b97499 reordered them to
    // Pulse / Settings (Timeline is currently commented out). Navigate to
    // it by LABEL rather than index, so a future reorder moves this test
    // with it instead of silently exercising whichever tab happens to sit
    // at a hardcoded position.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Confirms ChatSettingsStaticRows' real content rendered — i.e. this
    // test is actually exercising the plain-Column-with-no-scroll shape the
    // regression is about, not the null-conversation "unavailable" branch.
    expect(find.text('Search'), findsOneWidget);
    // The identity row (moved here from the old shared header) is real
    // content too — confirms it renders inside Settings, not above both
    // tabs.
    expect(find.text('Partner'), findsOneWidget); // activeConversation's name

    final tabBarBefore = tester.getTopLeft(find.byType(TabBar));

    // Drag from inside the TabBarView itself, not a specific text label —
    // 'Search' sits below the small test viewport at initial layout and
    // can't be hit-tested there, where the TabBarView's own body is always
    // large and on-screen.
    //
    // A small offset: a -300 drag now scrolls the tab bar fully off-screen
    // (0 widgets found by the later getTopLeft) rather than just moving
    // it — this only needs to prove movement, not scroll it away.
    await tester.drag(find.byType(TabBarView), const Offset(0, -40));
    await tester.pumpAndSettle();

    // The regression this guards: ChatSettingsStaticRows is a plain Column
    // with no scrollable of its own. Under the old bare-SliverFillRemaining
    // wrapping, its content had nowhere to go but overflow — takeException
    // would surface that RenderFlex "BOTTOM OVERFLOWED" error here.
    expect(tester.takeException(), isNull);

    final tabBarAfter = tester.getTopLeft(find.byType(TabBar));
    expect(tabBarAfter.dy, isNot(tabBarBefore.dy));
  });
}
