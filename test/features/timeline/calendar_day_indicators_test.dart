// Tests for the calendar's per-author story avatars, the event color
// key, and the day sheet a date opens.
//
// House pattern, matching story_calendar_test.dart: never mock
// SupabaseClient or Riverpod internals — override
// `storyReadGatewayProvider` with a fake `StoryReadGateway` and drive
// the real providers/widgets through a `ProviderScope`.
//
// The load-bearing assertion here is the PER-AUTHOR one: a day both
// partners posted on must draw TWO story avatars, not one. That is the
// entire reason migration 20260951010000 exists — before it,
// `list_story_day_counts` returned one row per day with no author
// breakdown, so the calendar could only ever say "this date has
// stories". A test that only checked "an avatar appears" would pass
// just as well against the old single-row shape and prove nothing.
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_indicators.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

const _myId = 'me-1';
const _partnerId = 'partner-1';
const _relationshipId = 'rel-1';

final _day = DateTime(2026, 6, 15);

/// Signed in as _myId, so the sheet can tell my ring from my partner's.
final _signedInUser = User(
  id: _myId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-06-01T00:00:00Z',
);

StoryDayCount _count({
  required String authorId,
  int itemCount = 1,
  int dayItemCount = 1,
  String? thumbnailKey = 'story-media/thumb.jpg',
  DateTime? occurredOn,
}) {
  return StoryDayCount(
    occurredOn: occurredOn ?? _day,
    authorId: authorId,
    itemCount: itemCount,
    dayItemCount: dayItemCount,
    newestThumbnailKey: thumbnailKey,
  );
}

StoryItem _item({
  required String id,
  String authorId = _partnerId,
  String mediaType = 'image',
  bool hasBeenViewed = false,
}) {
  return StoryItem(
    id: id,
    clientStoryId: 'client-$id',
    relationshipId: _relationshipId,
    authorId: authorId,
    mediaType: mediaType,
    mediaKey: 'story-media/$id.jpg',
    thumbnailKey: 'story-media/$id-thumb.jpg',
    mediaWidth: 1080,
    mediaHeight: 1920,
    durationMs: null,
    occurredOn: _day,
    createdAt: DateTime(2026, 6, 15, 10),
    // Deliberately already expired: an expired story still belongs to
    // its calendar day (stories spec §1/§3.2), and nothing in this
    // widget path may filter it out.
    expiresAt: DateTime(2026, 6, 16, 10),
    hasBeenViewed: hasBeenViewed,
  );
}

class _FakeGateway implements StoryReadGateway {
  _FakeGateway({
    List<StoryDayCount> dayCounts = const [],
    List<StoryItem> dayItems = const [],
  }) : _dayCounts = dayCounts,
       _dayItems = dayItems;

  final List<StoryDayCount> _dayCounts;
  final List<StoryItem> _dayItems;

  @override
  Future<List<StoryDayCount>> listDayCounts({
    required String relationshipId,
    required DateTime startOn,
    required DateTime endOn,
  }) async => List.of(_dayCounts);

  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async => StoryItemPage(items: List.of(_dayItems), nextCursor: null);

  @override
  Future<StoryItemPage> listActiveItems({
    required String relationshipId,
    required String authorId,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Future<List<StoryRingSummary>> getRingSummary({
    required String relationshipId,
  }) async => const [];

  @override
  Future<void> markViewed({required String storyItemId}) async {}

  @override
  Future<void> deleteItem({required String storyItemId}) async {}

  @override
  Future<StoryReplyTarget?> getReplyTarget({
    required String storyItemId,
  }) async => null;

  /// Returning a non-null URL would make the widget reach for a real
  /// network image in a widget test; null exercises the neutral-fill
  /// branch, which is all these assertions need (they count avatars,
  /// they do not assert on decoded pixels).
  @override
  Future<String?> signMediaUrl(String storageKey) async => null;

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream<void>.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  void disposeAllChannels() {}
}

Widget _wrap(Widget child, _FakeGateway gateway) {
  return ProviderScope(
    overrides: [
      storyReadGatewayProvider.overrideWithValue(gateway),
      currentUserProvider.overrideWithValue(_signedInUser),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('CalendarDayIndicators — per-author story avatars', () {
    testWidgets(
      'a day BOTH partners posted on draws TWO story avatars, not one',
      (tester) async {
        final gateway = _FakeGateway(
          dayCounts: [
            _count(authorId: _myId, dayItemCount: 2),
            _count(authorId: _partnerId, dayItemCount: 2),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            CalendarDayIndicators(
              relationshipId: _relationshipId,
              date: _day,
              eventTypes: const [],
              hasUpcoming: false,
            ),
            gateway,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('cal-story-$_myId')),
          findsOneWidget,
          reason: 'my own story on this day must draw its own avatar',
        );
        expect(
          find.byKey(const ValueKey('cal-story-$_partnerId')),
          findsOneWidget,
          reason: "the partner's story on this day must draw its own "
              'avatar — one avatar per author is the whole point of the '
              'per-author day-counts migration',
        );
      },
    );

    testWidgets('a day only one partner posted on draws exactly one avatar', (
      tester,
    ) async {
      final gateway = _FakeGateway(
        dayCounts: [_count(authorId: _partnerId)],
      );

      await tester.pumpWidget(
        _wrap(
          CalendarDayIndicators(
            relationshipId: _relationshipId,
            date: _day,
            eventTypes: const [],
            hasUpcoming: false,
          ),
          gateway,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cal-story-$_partnerId')), findsOneWidget);
      expect(find.byKey(const ValueKey('cal-story-$_myId')), findsNothing);
    });

    testWidgets('a day with no stories draws no story avatar', (tester) async {
      final gateway = _FakeGateway(
        // A story exists in the month, but on a DIFFERENT day.
        dayCounts: [
          _count(authorId: _partnerId, occurredOn: DateTime(2026, 6, 14)),
        ],
      );

      await tester.pumpWidget(
        _wrap(
          CalendarDayIndicators(
            relationshipId: _relationshipId,
            date: _day,
            eventTypes: const [],
            hasUpcoming: false,
          ),
          gateway,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cal-story-$_partnerId')), findsNothing);
    });

    testWidgets(
      'a null relationshipId renders no story avatars but still renders '
      'event indicators',
      (tester) async {
        final gateway = _FakeGateway(
          dayCounts: [_count(authorId: _partnerId)],
        );

        await tester.pumpWidget(
          _wrap(
            CalendarDayIndicators(
              relationshipId: null,
              date: _day,
              eventTypes: const ['milestone'],
              hasUpcoming: false,
            ),
            gateway,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('cal-story-$_partnerId')), findsNothing);
        expect(find.byIcon(Icons.flag), findsOneWidget);
      },
    );
  });

  group('CalendarDayIndicators — events', () {
    testWidgets(
      'each event type draws its own glyph, so the type survives a '
      'colorblind reading',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            CalendarDayIndicators(
              relationshipId: null,
              date: _day,
              eventTypes: const ['conflict'],
              hasUpcoming: false,
            ),
            _FakeGateway(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.bolt), findsOneWidget);
      },
    );

    testWidgets('an empty day with nothing at all renders nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CalendarDayIndicators(
            relationshipId: null,
            date: _day,
            eventTypes: const [],
            hasUpcoming: false,
          ),
          _FakeGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Row), findsNothing);
    });
  });

  group('CalendarLegend', () {
    testWidgets('renders only the event types actually present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CalendarLegend(
            eventTypes: ['milestone'],
            hasStories: true,
            hasUpcoming: true,
          ),
          _FakeGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Milestone'), findsOneWidget);
      expect(find.text('Story'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      // A type not present this month must not be advertised in the key.
      expect(find.text('Anniversary'), findsNothing);
      expect(find.text('Conflict'), findsNothing);
    });

    testWidgets('renders nothing when there is nothing to key', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const CalendarLegend(
            eventTypes: [],
            hasStories: false,
            hasUpcoming: false,
          ),
          _FakeGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Wrap), findsNothing);
    });
  });

  group('CalendarDaySheet', () {
    testWidgets(
      'a day BOTH partners posted on shows TWO rings, one per author — '
      'not one tile per story',
      (tester) async {
        final gateway = _FakeGateway(
          dayItems: [
            // Three items, two authors: the ring count must follow the
            // AUTHOR count (2), never the item count (3). A per-story
            // row would render three here.
            _item(id: 's1', authorId: _partnerId),
            _item(id: 's2', authorId: _myId),
            _item(id: 's3', authorId: _myId),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            CalendarDaySheet(
              relationshipId: _relationshipId,
              date: _day,
              events: const [],
              reminders: const [],
              planningEntries: const [],
            ),
            gateway,
          ),
        );
        await tester.pumpAndSettle();

        // Every item is already past its expiresAt — the rings must
        // still show, since expiry hides a story from the REEL, not
        // from the calendar.
        expect(find.text('3 stories'), findsOneWidget);
        expect(find.byType(StoryRing), findsNWidgets(2));
        expect(
          find.byKey(const ValueKey('day-story-ring-$_myId')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('day-story-ring-$_partnerId')),
          findsOneWidget,
        );

        // My ring carries BOTH my items as segments, the partner's
        // carries their one — proof the grouping is per author, not a
        // ring-per-item in disguise.
        // The ValueKey is on the _AuthorDayRing wrapper; the StoryRing
        // it builds is the descendant actually under test.
        StoryRing ringFor(String authorId) => tester.widget<StoryRing>(
          find.descendant(
            of: find.byKey(ValueKey('day-story-ring-$authorId')),
            matching: find.byType(StoryRing),
          ),
        );
        final mine = ringFor(_myId);
        final theirs = ringFor(_partnerId);
        expect(mine.segmentCount, 2);
        expect(mine.isMine, isTrue);
        expect(theirs.segmentCount, 1);
        expect(theirs.isMine, isFalse);
      },
    );

    testWidgets(
      'a day only one partner posted on shows exactly ONE ring',
      (tester) async {
        final gateway = _FakeGateway(
          dayItems: [
            _item(id: 's1', authorId: _partnerId),
            _item(id: 's2', authorId: _partnerId),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            CalendarDaySheet(
              relationshipId: _relationshipId,
              date: _day,
              events: const [],
              reminders: const [],
              planningEntries: const [],
            ),
            gateway,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(StoryRing), findsOneWidget);
        expect(
          find.byKey(const ValueKey('day-story-ring-$_myId')),
          findsNothing,
        );
      },
    );

    testWidgets(
      "my own ring renders every segment bright: hasBeenViewed on my own "
      'story means my PARTNER saw it, not that I did',
      (tester) async {
        final gateway = _FakeGateway(
          dayItems: [
            _item(id: 's1', authorId: _myId, hasBeenViewed: true),
            _item(id: 's2', authorId: _myId, hasBeenViewed: true),
            // The partner's, genuinely seen by me.
            _item(id: 's3', authorId: _partnerId, hasBeenViewed: true),
          ],
        );

        await tester.pumpWidget(
          _wrap(
            CalendarDaySheet(
              relationshipId: _relationshipId,
              date: _day,
              events: const [],
              reminders: const [],
              planningEntries: const [],
            ),
            gateway,
          ),
        );
        await tester.pumpAndSettle();

        // The ValueKey is on the _AuthorDayRing wrapper; the StoryRing
        // it builds is the descendant actually under test.
        StoryRing ringFor(String authorId) => tester.widget<StoryRing>(
          find.descendant(
            of: find.byKey(ValueKey('day-story-ring-$authorId')),
            matching: find.byType(StoryRing),
          ),
        );
        final mine = ringFor(_myId);
        final theirs = ringFor(_partnerId);
        // Reading hasBeenViewed literally for my own ring would fade
        // every segment of it forever, since the author never marks
        // their own story viewed.
        expect(mine.unviewedCount, 2);
        // The partner's IS viewed, so it correctly reads as seen.
        expect(theirs.unviewedCount, 0);
      },
    );

    testWidgets('a day with no stories renders no story section', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CalendarDaySheet(
            relationshipId: _relationshipId,
            date: _day,
            events: const [],
            reminders: const [],
            planningEntries: const [],
          ),
          _FakeGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('stories'), findsNothing);
      expect(find.bySemanticsLabel('Story from this day'), findsNothing);
    });

    testWidgets("lists the day's moments with their own type glyph", (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CalendarDaySheet(
            relationshipId: _relationshipId,
            date: _day,
            events: [
              TimelineEventModel(
                id: 'e1',
                relationshipId: _relationshipId,
                loggedBy: _myId,
                eventType: 'anniversary',
                title: 'Our first trip',
                note: 'Lisbon',
                occurredAt: _day,
                createdAt: _day,
              ),
            ],
            reminders: const [],
            planningEntries: const [],
          ),
          _FakeGateway(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Our first trip'), findsOneWidget);
      expect(find.text('Lisbon'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });
}
