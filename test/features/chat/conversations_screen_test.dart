import 'dart:async';

import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/conversations_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
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
    AsyncValue<List<Conversation>> conversationsState,
  ) {
    final container = ProviderContainer(
      overrides: [
        conversationsProvider.overrideWith(
          () => _FixedConversationsNotifier(conversationsState),
        ),
        journalEntriesProvider.overrideWith(
          () => _FixedJournalEntriesNotifier(),
        ),
        remindersListProvider.overrideWith(() => _FixedRemindersListNotifier()),
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
}
