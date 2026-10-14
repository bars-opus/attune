import 'dart:async';

import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/data/repositories/timeline_repository.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimelineRepository implements TimelineRepository {
  int monthFetches = 0;

  @override
  Future<List<TimelineEventModel>> getEventsForMonth({
    required String relationshipId,
    required DateTime month,
  }) async {
    monthFetches++;
    return const [];
  }

  @override
  Future<TimelineEventModel> createEvent({
    required String relationshipId,
    required String loggedBy,
    required String eventType,
    required String title,
    required DateTime occurredAt,
    String? note,
    int? moodScore,
    String visibility = 'shared',
  }) async => TimelineEventModel.fromJson({
    'id': 'e1',
    'relationship_id': relationshipId,
    'logged_by': loggedBy,
    'event_type': eventType,
    'title': title,
    'note': note,
    'mood_score': moodScore,
    'occurred_at': occurredAt.toIso8601String().split('T')[0],
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': null,
    'deleted_at': null,
  });

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeTimelineRepository repo) {
  final container = ProviderContainer(
    overrides: [
      timelineRepositoryProvider.overrideWithValue(repo),
      currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
      currentUserIdProvider.overrideWithValue('user-1'),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('timelineMonthKey drops the day and time', () {
    expect(
      timelineMonthKey(DateTime(2026, 10, 14, 15, 30, 12)),
      DateTime(2026, 10),
    );
  });

  test('logging a moment refreshes the month the screen is showing', () async {
    final repo = _FakeTimelineRepository();
    final container = _container(repo);
    final key = timelineMonthKey(DateTime.now());
    container.listen(timelineEventsProvider(key), (_, __) {});
    await container.read(timelineEventsProvider(key).future);
    expect(repo.monthFetches, 1);

    await container.read(
      createTimelineEventProvider((
        eventType: 'highlight',
        title: 'Picnic',
        occurredAt: DateTime.now(),
        note: null,
        moodScore: null,
        visibility: null,
      )).future,
    );
    await container.read(timelineEventsProvider(key).future);

    expect(repo.monthFetches, 2, reason: 'the shown month was invalidated');
  });

  test('a Together change signal refetches the moments', () async {
    final repo = _FakeTimelineRepository();
    final signals = StreamController<void>.broadcast();
    addTearDown(signals.close);
    final container = ProviderContainer(
      overrides: [
        timelineRepositoryProvider.overrideWithValue(repo),
        currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
        currentUserIdProvider.overrideWithValue('user-1'),
        togetherChangeSignalProvider.overrideWith((ref, id) => signals.stream),
      ],
    );
    addTearDown(container.dispose);
    final key = timelineMonthKey(DateTime.now());
    container.listen(timelineEventsProvider(key), (_, __) {});
    container.listen(timelineAutoRefreshProvider('rel-1'), (_, __) {});
    await container.read(timelineEventsProvider(key).future);
    expect(repo.monthFetches, 1);

    signals.add(null);
    await Future<void>.delayed(Duration.zero);
    await container.read(timelineEventsProvider(key).future);

    expect(repo.monthFetches, 2);
  });
}
