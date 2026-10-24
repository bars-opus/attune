import 'package:attune/features/stories/domain/story_ring_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the partner ring says how many are new (03 L2)', () {
    expect(
      storyRingPartnerLabel('Ama', active: 5, unviewed: 3),
      "Ama's story, 3 new of 5",
    );
    expect(
      storyRingPartnerLabel('Ama', active: 5, unviewed: 0),
      "Ama's story, 5 items, all seen",
    );
    expect(
      storyRingPartnerLabel('Ama', active: 1, unviewed: 4),
      "Ama's story, 1 new of 1",
    );
  });

  test('my ring keeps its count while posting', () {
    expect(storyRingMineLabel(1), 'Your story, 1 item');
    expect(storyRingMineLabel(3), 'Your story, 3 items');
    expect(storyRingPostingLabel(0), 'Your story, posting');
    expect(storyRingPostingLabel(2), 'Your story, posting, 2 posted');
  });

  test('a calendar day names whose stories they are', () {
    expect(
      storyDayRingLabel(mine: true, count: 2),
      'Your stories from this day, 2 items',
    );
    expect(
      storyDayRingLabel(mine: false, count: 1, partnerName: 'Kofi'),
      "Kofi's stories from this day, 1 item",
    );
    expect(
      storyDayRingLabel(mine: false, count: 3),
      "Your partner's stories from this day, 3 items",
    );
  });
}
