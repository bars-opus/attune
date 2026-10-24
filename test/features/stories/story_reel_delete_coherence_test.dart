// 05 #6 + coherence: deleting my story from the reel removes its thumbnail
// and media from this phone's caches and re-reads the calendar month, not
// only the Home ring.
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';
import 'support/ring_test_kit.dart' show NoopImageCache;

void main() {
  testWidgets('deleting my story evicts its media and refreshes its month', (
    tester,
  ) async {
    final images = NoopImageCache();
    final gateway = ScriptedReelGateway(
      active: kitItems(['m1', 'm2'], author: kitMe),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.ownReel,
      hold: const Duration(seconds: 30),
      extraOverrides: [chatImageCacheProvider.overrideWithValue(images)],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StoryReelScreen)),
    );
    final month = StoryDayRangeKey.month(relationshipId: kitRel, day: kitDay);
    final sub = container.listen(storyDayCountsProvider(month), (_, __) {});
    await settle(tester);
    final before = gateway.dayCountCalls;

    await confirmDelete(tester);
    await settle(tester);

    expect(
      images.removed,
      containsAll(['story-media/m1-thumb.jpg', 'story-media/m1.jpg']),
    );
    expect(gateway.dayCountCalls, before + 1);
    sub.close();
  });
}
