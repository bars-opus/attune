// Wave 5 (04 #4): the day ring's brightness now comes from the month's
// counts, so watching a partner's story from a day re-reads that month.
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

Future<({ScriptedReelGateway gateway, ProviderSubscription<Object?> sub})>
_open(WidgetTester tester, String author) async {
  final gateway = ScriptedReelGateway(
    day: kitItems(['s1', 's2'], author: author),
  );
  await pumpReel(
    tester,
    gateway: gateway,
    mode: KitMode.day,
    dayAuthorId: author,
    hold: const Duration(seconds: 30),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(StoryReelScreen)),
  );
  final month = StoryDayRangeKey.month(relationshipId: kitRel, day: kitDay);
  final sub = container.listen(storyDayCountsProvider(month), (_, __) {});
  await settle(tester);
  return (gateway: gateway, sub: sub);
}

void main() {
  testWidgets("watching a partner's unseen story from a day re-reads its "
      'month', (tester) async {
    final rig = await _open(tester, kitPartner);
    final before = rig.gateway.dayCountCalls;
    await tapRight(tester);
    await settle(tester);
    expect(rig.gateway.marked, contains('s2'));
    expect(rig.gateway.dayCountCalls, before + 1);
    rig.sub.close();
  });

  testWidgets('my own day ring never re-reads the month on view', (
    tester,
  ) async {
    final rig = await _open(tester, kitMe);
    final before = rig.gateway.dayCountCalls;
    await tapRight(tester);
    await settle(tester);
    expect(rig.gateway.marked, isEmpty);
    expect(rig.gateway.dayCountCalls, before);
    rig.sub.close();
  });

  testWidgets("watching a partner's unseen story from a map pin re-reads "
      'its month', (tester) async {
    final items = kitItems(['s1', 's2']);
    final gateway = ScriptedReelGateway();
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.places,
      placeItems: items,
      hold: const Duration(seconds: 30),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StoryReelScreen)),
    );
    final month = StoryDayRangeKey.month(relationshipId: kitRel, day: kitDay);
    final sub = container.listen(storyDayCountsProvider(month), (_, __) {});
    await settle(tester);
    final before = gateway.dayCountCalls;
    await tapRight(tester);
    await settle(tester);
    expect(gateway.marked, contains('s2'));
    expect(gateway.dayCountCalls, before + 1);
    sub.close();
  });

  // Fix round 1 (review #2): a view from the Conversations ring re-reads
  // the month too, or the day sheet keeps the ring bright.
  testWidgets("watching a partner's unseen story from their ring re-reads "
      'its month', (tester) async {
    final gateway = ScriptedReelGateway(active: kitItems(['s1', 's2']));
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.partnerReel,
      hold: const Duration(seconds: 30),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(StoryReelScreen)),
    );
    final month = StoryDayRangeKey.month(relationshipId: kitRel, day: kitDay);
    final sub = container.listen(storyDayCountsProvider(month), (_, __) {});
    await settle(tester);
    final before = gateway.dayCountCalls;
    await tapRight(tester);
    await settle(tester);
    expect(gateway.marked, contains('s2'));
    expect(gateway.dayCountCalls, before + 1);
    sub.close();
  });
}
