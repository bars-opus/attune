import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/data/repositories/reminders_repository.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRemindersRepository implements RemindersRepository {
  _FakeRemindersRepository({this.linkShouldThrow = false});

  final bool linkShouldThrow;
  final List<({String reminderId, String timelineEventId})> linkCalls = [];

  @override
  Future<void> linkReminderToTimelineEvent({
    required String reminderId,
    required String timelineEventId,
  }) async {
    if (linkShouldThrow) {
      throw Exception('network error');
    }
    linkCalls.add((reminderId: reminderId, timelineEventId: timelineEventId));
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TimelineEventModel _event({String id = 'evt-1', String eventType = 'milestone'}) {
  return TimelineEventModel(
    id: id,
    relationshipId: 'rel-1',
    loggedBy: 'user-1',
    eventType: eventType,
    title: 'First trip together',
    occurredAt: DateTime(2026, 6, 4),
    createdAt: DateTime(2026, 6, 4),
  );
}

ReminderModel _reminder({String id = 'rem-1'}) {
  return ReminderModel(
    id: id,
    relationshipId: 'rel-1',
    createdBy: 'user-1',
    reminderType: 'anniversary',
    title: 'First trip together',
    remindAt: DateTime(2026, 6, 4),
    recurrence: 'yearly',
    sent: false,
    createdAt: DateTime(2026, 6, 4),
    updatedAt: DateTime(2026, 6, 4),
  );
}

void main() {
  group('LogMomentDetailsScreen dialog eligibility', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      required String eventType,
      String? editEventId,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LogMomentDetailsScreen(
              eventType: eventType,
              editEventId: editEventId,
            ),
          ),
        ),
      );
    }

    testWidgets('milestone and anniversary are eligible event types', (
      tester,
    ) async {
      expect(
        const LogMomentDetailsScreen(eventType: 'milestone').isEligibleForReminderOffer,
        isTrue,
      );
      expect(
        const LogMomentDetailsScreen(eventType: 'anniversary').isEligibleForReminderOffer,
        isTrue,
      );
    });

    testWidgets('conflict, highlight, and first are not eligible', (
      tester,
    ) async {
      expect(
        const LogMomentDetailsScreen(eventType: 'conflict').isEligibleForReminderOffer,
        isFalse,
      );
      expect(
        const LogMomentDetailsScreen(eventType: 'highlight').isEligibleForReminderOffer,
        isFalse,
      );
      expect(
        const LogMomentDetailsScreen(eventType: 'first').isEligibleForReminderOffer,
        isFalse,
      );
    });
  });
}
