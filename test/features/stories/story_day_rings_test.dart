import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/domain/story_day_rings.dart';
import 'package:flutter_test/flutter_test.dart';

final _day = DateTime(2026, 6, 15);

StoryItem _item(String id, String author, {bool viewed = false}) => StoryItem(
  id: id,
  clientStoryId: 'c-$id',
  relationshipId: 'rel-1',
  authorId: author,
  mediaType: 'image',
  mediaKey: 'story-media/$id.jpg',
  thumbnailKey: 'story-media/$id-thumb.jpg',
  mediaWidth: 1080,
  mediaHeight: 1920,
  occurredOn: _day,
  createdAt: _day,
  expiresAt: _day.add(const Duration(hours: 24)),
  hasBeenViewed: viewed,
);

StoryDayCount _count(String author, int n, int day, {String? key}) =>
    StoryDayCount(
      occurredOn: _day,
      authorId: author,
      itemCount: n,
      dayItemCount: day,
      newestThumbnailKey: key ?? 'story-media/$author-newest.jpg',
      newestCreatedAt: _day,
    );

void main() {
  test(
    'counts and authors come from the whole day, not the first page (04 #4)',
    () {
      final result = storyDayAuthorRings(
        day: _day,
        counts: [_count('me', 50, 60), _count('partner', 10, 60)],
        items: [for (var i = 0; i < 50; i++) _item('m$i', 'me')],
        myId: 'me',
      );
      expect(result.total, 60);
      expect(result.rings.map((r) => (r.authorId, r.count)), [
        ('me', 50),
        ('partner', 10),
      ]);
      expect(result.rings.last.thumbnailKey, 'story-media/partner-newest.jpg');
    },
  );

  test('loaded items still draw the rings when the counts failed', () {
    final result = storyDayAuthorRings(
      day: _day,
      counts: null,
      items: [
        _item('p1', 'partner', viewed: true),
        _item('m1', 'me'),
        _item('p2', 'partner'),
      ],
      myId: 'me',
    );
    expect(result.total, 3);
    expect(result.rings.map((r) => r.authorId), ['me', 'partner']);
    expect(result.rings.first.unviewed, 1);
    expect(result.rings.last.unviewed, 1);
    expect(result.rings.last.thumbnailKey, 'story-media/p2-thumb.jpg');
  });

  test('nothing that day, nothing drawn', () {
    final result = storyDayAuthorRings(
      day: _day,
      counts: const [],
      items: const [],
      myId: 'me',
    );
    expect(result.rings, isEmpty);
    expect(result.total, 0);
  });

  test(
    'a past day whose newest story went loses its thumbnail key (05 #6)',
    () {
      final before = [_count('partner', 2, 2, key: 'b')];
      final deleted = [
        StoryDayCount(
          occurredOn: _day,
          authorId: 'partner',
          itemCount: 1,
          dayItemCount: 1,
          newestThumbnailKey: 'a',
          newestCreatedAt: _day.subtract(const Duration(hours: 1)),
        ),
      ];
      expect(storyDayCountDroppedKeys(before, deleted), {'b'});
      expect(storyDayCountDroppedKeys(before, const []), {'b'});
      final newer = [
        StoryDayCount(
          occurredOn: _day,
          authorId: 'partner',
          itemCount: 3,
          dayItemCount: 3,
          newestThumbnailKey: 'c',
          newestCreatedAt: _day.add(const Duration(hours: 1)),
        ),
      ];
      expect(storyDayCountDroppedKeys(before, newer), isEmpty);
      expect(storyDayCountDroppedKeys(null, deleted), isEmpty);
    },
  );

  test("the server's unviewed count wins over a partial first page "
      '(Wave 5)', () {
    final day = DateTime(2026, 10, 21);
    final counts = [
      StoryDayCount(
        occurredOn: day,
        authorId: 'partner',
        itemCount: 70,
        dayItemCount: 70,
        unviewedCount: 61,
      ),
    ];
    final loaded = [
      for (var i = 0; i < 50; i++)
        StoryItem(
          id: 'p$i',
          clientStoryId: 'c$i',
          relationshipId: 'r',
          authorId: 'partner',
          mediaType: 'image',
          mediaKey: 'k$i',
          thumbnailKey: 't$i',
          mediaWidth: 1,
          mediaHeight: 1,
          occurredOn: day,
          createdAt: DateTime.utc(2026, 10, 21, 8).add(Duration(minutes: i)),
          expiresAt: DateTime.utc(2026, 10, 22, 8).add(Duration(minutes: i)),
          hasBeenViewed: i < 20,
        ),
    ];
    final result = storyDayAuthorRings(
      day: day,
      counts: counts,
      items: loaded,
      myId: 'me',
    );
    expect(result.rings.single.count, 70);
    expect(
      result.rings.single.unviewed,
      61,
      reason: 'not the 30 unseen on page one',
    );
    final old = storyDayAuthorRings(
      day: day,
      counts: [
        StoryDayCount(
          occurredOn: day,
          authorId: 'partner',
          itemCount: 70,
          dayItemCount: 70,
        ),
      ],
      items: loaded,
      myId: 'me',
    );
    expect(
      old.rings.single.unviewed,
      30,
      reason: 'an older server: the loaded items decide',
    );
  });

  // Fix round 1 (review #2): stale counts never outshine fresh items that
  // cover the author's whole day.
  test('loaded items that cover the whole day win over the counts', () {
    final result = storyDayAuthorRings(
      day: _day,
      counts: [
        StoryDayCount(
          occurredOn: _day,
          authorId: 'partner',
          itemCount: 3,
          dayItemCount: 3,
          unviewedCount: 3,
        ),
      ],
      items: [
        for (var i = 0; i < 3; i++) _item('p$i', 'partner', viewed: true),
      ],
      myId: 'me',
    );
    expect(result.rings.single.count, 3);
    expect(result.rings.single.unviewed, 0);
  });
}
