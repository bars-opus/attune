import 'dart:async';

// test/features/couple_map/story_pin_controller_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _osu = StoryPlaceDraft(lat: 5.556, lng: -0.197, label: 'Near Osu, Accra');

void main() {
  test('first time: off, and nothing is looked up', () async {
    final r = FakeStoryPlaceResolver(_osu);
    final c = StoryPinController(
      store: MemoryCoupleMapLocalStore(),
      resolver: r,
      paused: false,
    );
    await c.init();
    expect(c.on, isFalse);
    expect(r.calls, 0);
    expect(await c.placeForPost(), isNull);
  });

  test(
    'turning it on looks the place up once, previews it, and is remembered',
    () async {
      final s = MemoryCoupleMapLocalStore();
      final r = FakeStoryPlaceResolver(_osu);
      final c = StoryPinController(store: s, resolver: r, paused: false);
      await c.init();
      await c.setOn(true);
      expect((c.on, r.calls, c.place?.label), (true, 1, 'Near Osu, Accra'));
      expect((await c.placeForPost())!.label, 'Near Osu, Accra');
      expect(await readPinLastChoice(s), isTrue);
    },
  );

  test(
    'remembered on: starts on and looks up (the author\'s own choice)',
    () async {
      final s = MemoryCoupleMapLocalStore();
      await writePinLastChoice(s, true);
      final r = FakeStoryPlaceResolver(_osu);
      final c = StoryPinController(store: s, resolver: r, paused: false);
      await c.init();
      expect((c.on, r.calls), (true, 1));
    },
  );

  test(
    'paused: starts off with the paused notice, even if remembered on, and looks nothing up',
    () async {
      final s = MemoryCoupleMapLocalStore();
      await writePinLastChoice(s, true);
      final r = FakeStoryPlaceResolver(_osu);
      final c = StoryPinController(store: s, resolver: r, paused: true);
      await c.init();
      expect((c.on, c.notice, r.calls), (false, StoryPinNotice.paused, 0));
      // Starts off, but stays the author's choice (spec §3.3, §4.5).
      await c.setOn(true);
      expect((c.on, c.notice, r.calls), (true, null, 1));
    },
  );

  test(
    'shutter during the lookup waits for it, so an "on" story is pinned (not silently unpinned)',
    () async {
      final r = FakeStoryPlaceResolver(_osu)..hold = Completer<void>();
      final c = StoryPinController(
        store: MemoryCoupleMapLocalStore(),
        resolver: r,
        paused: false,
      );
      await c.init();
      unawaited(c.setOn(true));
      final posted = c.placeForPost();
      r.hold!.complete();
      expect((await posted)?.label, 'Near Osu, Accra');
    },
  );

  test(
    'near the home area: turns off with the notice; turning it back on sticks',
    () async {
      final s = MemoryCoupleMapLocalStore();
      await writeHomeArea(s, const HomeArea(lat: 5.5561, lng: -0.1971));
      final c = StoryPinController(
        store: s,
        resolver: FakeStoryPlaceResolver(_osu),
        paused: false,
      );
      await c.init();
      await c.setOn(true);
      expect((c.on, c.notice), (false, StoryPinNotice.nearHome));
      expect(await c.placeForPost(), isNull);
      await c.setOn(true); // the author insists
      expect(c.on, isTrue);
      expect(await c.placeForPost(), isNotNull);
    },
  );

  test(
    'no fix: notice, and the story posts without a place (Review Focus 3)',
    () async {
      final c = StoryPinController(
        store: MemoryCoupleMapLocalStore(),
        resolver: FakeStoryPlaceResolver(null),
        paused: false,
      );
      await c.init();
      await c.setOn(true);
      expect((c.on, c.notice), (true, StoryPinNotice.notFound));
      expect(await c.placeForPost(), isNull);
    },
  );

  test('turning it off forgets the place and is remembered', () async {
    final s = MemoryCoupleMapLocalStore();
    final c = StoryPinController(
      store: s,
      resolver: FakeStoryPlaceResolver(_osu),
      paused: false,
    );
    await c.init();
    await c.setOn(true);
    await c.setOn(false);
    expect((c.on, c.place), (false, null));
    expect(await readPinLastChoice(s), isFalse);
  });

  test(
    'a slow lookup that finishes after the switch went off is discarded',
    () async {
      final r = FakeStoryPlaceResolver(_osu)..hold = Completer<void>();
      final c = StoryPinController(
        store: MemoryCoupleMapLocalStore(),
        resolver: r,
        paused: false,
      );
      await c.init();
      final turning = c.setOn(true);
      await c.setOn(false);
      r.hold!.complete();
      await turning;
      expect((c.on, c.place), (false, null));
    },
  );

  test(
    'a shutter before the paused check returns still pins a remembered "on"',
    () async {
      final s = MemoryCoupleMapLocalStore();
      await writePinLastChoice(s, true);
      final check = Completer<bool>();
      final c = StoryPinController(
        store: s,
        resolver: FakeStoryPlaceResolver(_osu),
        paused: false,
        pausedCheck: check.future,
      );
      unawaited(c.init());
      final posted = c.placeForPost();
      check.complete(false);
      expect((await posted)?.label, 'Near Osu, Accra');
    },
  );

  test(
    'a paused check that lands after the author already chose leaves their choice',
    () async {
      final check = Completer<bool>();
      final c = StoryPinController(
        store: MemoryCoupleMapLocalStore(),
        resolver: FakeStoryPlaceResolver(_osu),
        paused: false,
        pausedCheck: check.future,
      );
      unawaited(c.init());
      await c.setOn(true);
      check.complete(true);
      await c.init();
      expect(c.on, isTrue);
    },
  );

  test(
    'remembered on never prompts at camera open; only a tap may ask (Review Focus 2)',
    () async {
      final s = MemoryCoupleMapLocalStore();
      await writePinLastChoice(s, true);
      final r = FakeStoryPlaceResolver(_osu);
      final c = StoryPinController(store: s, resolver: r, paused: false);
      await c.init();
      await c.placeForPost();
      expect(r.asks, [false]);
      await c.setOn(false);
      await c.setOn(true);
      expect(r.asks, [false, true]);
    },
  );

  test(
    'no permission: "allow location", nothing pinned, Settings is the way',
    () async {
      final r =
          FakeStoryPlaceResolver()..problem = StoryPlaceProblem.noPermission;
      final c = StoryPinController(
        store: MemoryCoupleMapLocalStore(),
        resolver: r,
        paused: false,
      );
      await c.init();
      await c.setOn(true);
      expect(
        (c.on, c.notice, c.canAsk),
        (true, StoryPinNotice.allowLocation, false),
      );
      expect(await c.placeForPost(), isNull);
    },
  );

  test(
    'denied but still askable: "allow location", and a tap may ask',
    () async {
      final s = MemoryCoupleMapLocalStore();
      await writePinLastChoice(s, true);
      final r = FakeStoryPlaceResolver()..problem = StoryPlaceProblem.needsAsk;
      final c = StoryPinController(store: s, resolver: r, paused: false);
      await c.init();
      await c.placeForPost();
      expect((c.notice, c.canAsk), (StoryPinNotice.allowLocation, true));
    },
  );

  test('iOS Precise Location off: pinned, and marked approximate', () async {
    final r = FakeStoryPlaceResolver(_osu)..approximate = true;
    final c = StoryPinController(
      store: MemoryCoupleMapLocalStore(),
      resolver: r,
      paused: false,
    );
    await c.init();
    await c.setOn(true);
    expect(c.approximate, isTrue);
    expect((await c.placeForPost())?.label, 'Near Osu, Accra');
  });

  test('location services off: "turn on location", not "allow"', () async {
    final r = FakeStoryPlaceResolver()..problem = StoryPlaceProblem.servicesOff;
    final c = StoryPinController(
      store: MemoryCoupleMapLocalStore(),
      resolver: r,
      paused: false,
    );
    await c.init();
    await c.setOn(true);
    expect((c.notice, c.canAsk), (StoryPinNotice.turnOnLocation, false));
  });
}
