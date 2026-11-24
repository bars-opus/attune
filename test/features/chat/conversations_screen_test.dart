import 'dart:async';

import 'package:attune/core/flags/couple_link_couple_side.dart';
import 'package:attune/core/flags/couple_link_flag.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/link/link_offer_card.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Conversation _conversation({String id = 'c1', int unreadCount = 0}) {
  return Conversation(
    id: id,
    relationshipId: 'rel-1',
    partnerId: 'partner-1',
    name: 'Partner',
    updatedAt: DateTime.utc(2026, 8, 1),
    relationshipStatus: 'active',
    availability: ConversationAvailability.active,
    unreadCount: unreadCount,
  );
}

/// Fixed AsyncValue notifier for tests. build() resolves to whatever value
/// the initial AsyncData/AsyncLoading-with-no-value case needs; the
/// loading-with-previous-value case (a background refresh) is instead
/// produced by the test assigning `state` directly on the live notifier
/// AFTER build() has settled — assigning `state` mid-build() confused
/// Riverpod's own bookkeeping into reporting AsyncError.
class _FixedConversationsNotifier extends ConversationsNotifier {
  _FixedConversationsNotifier(this._initial);
  final AsyncValue<List<Conversation>> _initial;

  @override
  Future<List<Conversation>> build() {
    if (_initial.hasValue) {
      return Future.value(_initial.value);
    }
    // No value yet — mirrors ConversationsNotifier's own first-ever-launch
    // path (no cache, network pending): stays pending for the test's
    // lifetime, so the provider's own AsyncLoading (no previous value) is
    // what the widget sees.
    return Completer<List<Conversation>>().future;
  }
}

class _FixedJournalEntriesNotifier extends JournalEntriesNotifier {
  @override
  Future<List<JournalEntry>> build() async => const [];
}

class _FixedRemindersListNotifier extends RemindersListNotifier {
  @override
  Future<List<ReminderModel>> build() async => const [];
}

void main() {
  ({Widget widget, ProviderContainer container}) wrap(
    AsyncValue<List<Conversation>> conversationsState, {
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        conversationsProvider.overrideWith(
          () => _FixedConversationsNotifier(conversationsState),
        ),
        journalEntriesProvider.overrideWith(
          () => _FixedJournalEntriesNotifier(),
        ),
        remindersListProvider.overrideWith(() => _FixedRemindersListNotifier()),
        // Spec 2 W9 final client fix (M-8): the couple link's flag read
        // answers (off: no couple_link) rather than failing on a missing
        // Supabase, so a screen that asks it runs the answered branch and never
        // registers the failed branch's resume and reconnect retries.
        coupleLinkFlagReadProvider.overrideWithValue(
          () async => const {'state': 'not_started'},
        ),
        ...extra,
      ],
    );
    return (
      widget: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => const ConversationsScreen(),
          ),
        ),
      ),
      container: container,
    );
  }

  // The cards settle in, in turn, the first time the screen shows its
  // content in a session; never again until the app restarts, and not at
  // all with reduce motion.
  double opacityOf(WidgetTester tester, String text) => tester
      .widgetList<FadeTransition>(find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)))
      .fold(1.0, (o, f) => o * f.opacity.value);

  testWidgets('the cards settle in the first time, then never replay', (tester) async {
    final harness = wrap(AsyncData([_conversation()]));
    addTearDown(harness.container.dispose);
    await tester.pumpWidget(harness.widget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, 'Partner'), lessThan(1), reason: 'settling in');
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'Partner'), 1);

    // Back to Conversations later in the session: there at once.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp(
        home: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const ConversationsScreen()),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, 'Partner'), 1);
  });

  testWidgets('with reduce motion the cards are simply there', (tester) async {
    final harness = wrap(AsyncData([_conversation()]));
    addTearDown(harness.container.dispose);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: harness.widget,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, 'Partner'), 1);
  });

  testWidgets(
    'a background refresh (loading with a previous value) keeps showing the '
    'cached conversation instead of blanking to a spinner',
    (tester) async {
      final cached = _conversation(unreadCount: 3);
      final harness = wrap(AsyncData([cached]));
      addTearDown(harness.container.dispose);

      await tester.pumpWidget(harness.widget);
      await tester.pump();
      expect(find.text('Partner'), findsOneWidget);

      // Simulate the background-refresh tick: the real ConversationsNotifier
      // sets `state = AsyncData(...)` after a successful refetch, but while
      // that refetch is in flight Riverpod's own framework reports
      // AsyncLoading-with-previous-value on the SAME provider — reproduce
      // that exact transition here.
      harness.container
          .read(conversationsProvider.notifier)
          .state = const AsyncLoading<List<Conversation>>().copyWithPrevious(
        AsyncData([cached]),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Partner'), findsOneWidget);
    },
  );

  testWidgets(
    'a background refresh keeps showing the cached list instead of the '
    'empty-state prompt',
    (tester) async {
      final cached = _conversation();
      final harness = wrap(AsyncData([cached]));
      addTearDown(harness.container.dispose);

      await tester.pumpWidget(harness.widget);
      await tester.pump();

      harness.container
          .read(conversationsProvider.notifier)
          .state = const AsyncLoading<List<Conversation>>().copyWithPrevious(
        AsyncData([cached]),
      );
      await tester.pump();

      expect(find.text('No relationship chat is available yet.'), findsNothing);
    },
  );

  testWidgets(
    'the very first load ever (no previous value) still shows the spinner',
    (tester) async {
      final harness = wrap(const AsyncLoading<List<Conversation>>());
      addTearDown(harness.container.dispose);

      await tester.pumpWidget(harness.widget);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  // Spec 2 W9 final client fix (M-8): signed in, the couple link's flag read
  // answers (the success branch, not a missing Supabase): one read; off, no
  // couple-side call; on with nothing to say, one offer read; either way
  // the Relationship home's cards are exactly as before.
  for (final on in [false, true]) {
    testWidgets('signed in, the couple link answered ${on ? 'on' : 'off'}: '
        'the cards are as before', (tester) async {
      var reads = 0;
      final calls = <String>[];
      final harness = wrap(
        AsyncData([_conversation()]),
        extra: [
          datingAccountProvider.overrideWithValue('u-1'),
          coupleLinkFlagReadProvider.overrideWithValue(() async {
            reads++;
            return {'state': 'not_started', if (on) 'couple_link': true};
          }),
          coupleLinkCoupleCallProvider.overrideWithValue((fn, _) async {
            calls.add(fn);
            return const {'ok': true, 'offer': null};
          }),
        ],
      );
      addTearDown(harness.container.dispose);
      await tester.pumpWidget(harness.widget);
      await tester.pumpAndSettle();
      expect(find.text('Partner'), findsOneWidget);
      expect(find.byType(DatingLinkOfferCard), findsNothing);
      expect(reads, 1);
      expect(calls, on ? ['get_dating_post_link_offer'] : isEmpty);
    });
  }
}
