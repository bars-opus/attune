import 'dart:async';

// test/features/couple_map/couple_map_tab_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/couple_map/presentation/map/couple_map_controller.dart';
import 'package:attune/features/couple_map/presentation/screens/couple_map_tab.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

import 'support/tab_harness.dart';

void main() {
  testWidgets(
    'both sharing: two areas at cell centres, fitted once, the card and the chip',
    (t) async {
      final h = TabHarness([selfRow, partnerRow()]);
      await h.pump(t);
      final c = h.view.controller;
      expect(c.lastAreas.map((a) => a.who), [
        PresenceWho.self,
        PresenceWho.partner,
      ]);
      expect(
        c.presences.last.$2.keys,
        containsAll([PresenceWho.self, PresenceWho.partner]),
      );
      expect(c.fits, hasLength(1));
      expect(c.fits.single.$1, hasLength(2));
      expect(find.text('Sharing my area with Kofi'), findsOneWidget);
      expect(find.textContaining('5.1k km apart · in London'), findsOneWidget);
    },
  );

  testWidgets(
    'a fading partner is drawn at half opacity, with no time anywhere',
    (t) async {
      final h = TabHarness([selfRow, partnerRow(freshness: 'fading')]);
      await h.pump(t);
      expect(
        h.view.controller.lastAreas.last.opacity,
        CoupleMapConfig.fadingOpacity,
      );
      for (final banned in ['ago', 'online', 'last seen']) {
        expect(
          find.textContaining(RegExp(banned, caseSensitive: false)),
          findsNothing,
        );
      }
    },
  );

  testWidgets('no partner row: only my area and one neutral line', (t) async {
    final h = TabHarness([selfRow]);
    await h.pump(t);
    expect(h.view.controller.lastAreas.map((a) => a.who), [PresenceWho.self]);
    expect(find.text('Just you on the map right now'), findsOneWidget);
  });

  testWidgets(
    'partner disappears on refresh: their area and the card go (Review Focus 1)',
    (t) async {
      final h = TabHarness([selfRow, partnerRow()]);
      await h.pump(t);
      h.rows = [selfRow];
      final container = ProviderScope.containerOf(
        t.element(find.byType(CoupleMapTab)),
      );
      container.invalidate(coupleMapPresenceProvider('r1'));
      await t.pumpAndSettle();
      expect(h.view.controller.lastAreas.map((a) => a.who), [PresenceWho.self]);
      expect(find.textContaining('km apart'), findsNothing);
      expect(find.text('Just you on the map right now'), findsOneWidget);
    },
  );

  testWidgets(
    'not sharing: the onboarding line opens the sheet; never sampled or prompted',
    (t) async {
      final h = TabHarness(const []);
      await h.pump(t);
      expect(h.sampler.sampled, 0);
      expect(h.sampler.asked, 0);
      await t.tap(
        find.text(
          'See how far apart you are — shares your neighbourhood, never your address',
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Share my approximate area'), findsOneWidget);
    },
  );

  testWidgets('location off: the chip says so and the notice opens settings', (
    t,
  ) async {
    final h = TabHarness([selfRow])
      ..sampler.accessValue = LocationAccess.denied;
    await h.pump(t);
    expect(find.text('Location is off for Attune'), findsOneWidget);
    await t.tap(find.text('Turn on location for Attune to share your area'));
    await t.pumpAndSettle();
    expect(h.sampler.openedSettings, 1);
  });

  testWidgets(
    'load error: the list content replaces the map; the chip still works (Review Focus 5)',
    (t) async {
      final h = TabHarness([selfRow, partnerRow()]);
      await h.pump(t);
      h.view.failLoad();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake-map')), findsNothing);
      expect(find.textContaining('London'), findsWidgets);
      expect(find.text('Sharing my area with Kofi'), findsOneWidget);
    },
  );

  testWidgets('empty token: no map is built, the list shows', (t) async {
    final h = TabHarness([selfRow])..token = '';
    await h.pump(t);
    expect(h.view.built, 0);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('style toggle switches to satellite and back', (t) async {
    final h = TabHarness([selfRow]);
    await h.pump(t);
    await t.tap(find.byTooltip('Satellite view'));
    await t.pumpAndSettle();
    expect(h.view.controller.styles.last.$1, CoupleMapStyle.satellite);
    expect(find.byTooltip('Map view'), findsOneWidget);
  });

  testWidgets('recentre flies normally', (t) async {
    final h = TabHarness([selfRow, partnerRow()]);
    await h.pump(t);
    await t.tap(find.byTooltip('Recentre on us'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits.last.$2, isTrue);
  });

  testWidgets('recentre with reduced motion jumps instead of flying', (
    t,
  ) async {
    final h = TabHarness([selfRow, partnerRow()])..reduceMotion = true;
    await h.pump(t);
    await t.tap(find.byTooltip('Recentre on us'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits.last.$2, isFalse);
  });

  testWidgets('theme change updates the light preset (Review Focus 3)', (
    t,
  ) async {
    final h = TabHarness([selfRow]);
    await h.pump(t);
    h.themeMode = ThemeMode.dark;
    await h.repump(t);
    expect(h.view.controller.styles.last, (CoupleMapStyle.standard, true));
  });

  testWidgets('every control has a label and a tap action (spec §3.5)', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final h = TabHarness([selfRow, partnerRow()]);
    await h.pump(t);
    for (final label in [
      'Satellite view',
      'Recentre on us',
      'List',
      'Zoom in',
      'Zoom out',
    ]) {
      final f = find.bySemanticsLabel(label);
      expect(f, findsOneWidget, reason: label);
      expect(
        t.getSemantics(f),
        containsSemantics(hasTapAction: true),
        reason: label,
      );
    }
    semantics.dispose();
  });

  testWidgets(
    'offline at open: says so plainly, retries on tap, never claims Off (checklist 1.3)',
    (t) async {
      final h = TabHarness([selfRow]);
      h.gateway.handlers['couple_map_presence'] =
          (_) => throw Exception('offline');
      await h.pump(t);
      expect(find.text("Couldn't load your map. Try again."), findsOneWidget);
      expect(find.text('Off'), findsNothing);
      h.gateway.handlers['couple_map_presence'] = (_) => h.rows;
      await t.tap(find.text("Couldn't load your map. Try again."));
      await t.pumpAndSettle();
      expect(find.text('Just you on the map right now'), findsOneWidget);
    },
  );

  testWidgets(
    'a slow avatar never brings back a partner who has since gone (Review Focus 1)',
    (t) async {
      final h = TabHarness([selfRow, partnerRow()]);
      final slow = Completer<void>();
      h.pins.hold['K'] = slow; // the partner's pin renders slowly
      await h.pump(t);
      h.rows = [selfRow];
      final container = ProviderScope.containerOf(
        t.element(find.byType(CoupleMapTab)),
      );
      container.invalidate(coupleMapPresenceProvider('r1'));
      await t.pumpAndSettle();
      slow.complete(); // the stale draw finishes last
      await t.pumpAndSettle();
      expect(h.view.controller.lastAreas.map((a) => a.who), [PresenceWho.self]);
    },
  );

  testWidgets(
    'offline at open with no map: the list says so and retrying brings the map back',
    (t) async {
      final h = TabHarness([selfRow]);
      h.gateway.handlers['couple_map_presence'] =
          (_) => throw Exception('offline');
      await h.pump(t);
      h.view.failLoad();
      await t.pumpAndSettle();
      expect(find.text("Couldn't load your map. Try again."), findsOneWidget);
      h.gateway.handlers['couple_map_presence'] = (_) => h.rows;
      await t.tap(find.text("Couldn't load your map. Try again."));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake-map')), findsOneWidget);
      expect(find.text('Just you on the map right now'), findsOneWidget);
    },
  );

  testWidgets(
    'the Mapbox logo and attribution sit above the tallest card (Mapbox terms)',
    (t) async {
      final h = TabHarness([selfRow, partnerRow()]);
      await h.pump(t);
      expect(
        h.view.builtOrnamentBottom,
        greaterThanOrEqualTo(Spacing.md + CoupleMapConfig.cardMaxHeight),
      );
    },
  );

  testWidgets(
    'no pinned stories: no Stories button, no pins, and a one-time hint',
    (t) async {
      final h = TabHarness([selfRow]);
      await h.pump(t);
      expect(find.byTooltip(RegExp('Stories')), findsNothing);
      expect(
        find.text('Stories you pin from the camera appear here'),
        findsOneWidget,
      );
      expect(h.local.values[CoupleMapLocalKeys.storiesHintSeen], 'true');
      // Second visit: no hint.
      await t.pumpWidget(const SizedBox());
      await h.pump(t);
      expect(
        find.text('Stories you pin from the camera appear here'),
        findsNothing,
      );
    },
  );

  testWidgets('pinned stories are drawn; the Stories button appears', (
    t,
  ) async {
    final h = TabHarness([selfRow])
      ..places = [
        storyPlaceRow('s1', author: 'kofi'),
        storyPlaceRow('s2', author: 'ama'),
      ];
    await h.pump(t);
    expect(
      h.view.controller.stories.last.$1.map((p) => p.storyItemId).toSet(),
      {'s1', 's2'},
    );
    expect(find.byTooltip('Stories: both of you'), findsOneWidget);
  });

  testWidgets('the filter cycles and rebuilds the story set (Review Focus 5)', (
    t,
  ) async {
    final h = TabHarness([selfRow])
      ..places = [
        storyPlaceRow('s1', author: 'kofi'),
        storyPlaceRow('s2', author: 'ama'),
      ];
    await h.pump(t);
    await t.tap(find.byTooltip('Stories: both of you'));
    await t.pumpAndSettle();
    expect(h.view.controller.stories.last.$1.map((p) => p.storyItemId), ['s2']);
    expect(find.byTooltip('Stories: mine'), findsOneWidget);
    await t.tap(find.byTooltip('Stories: mine'));
    await t.pumpAndSettle();
    expect(h.view.controller.stories.last.$1.map((p) => p.storyItemId), ['s1']);
    expect(find.byTooltip("Stories: Kofi's"), findsOneWidget);
  });

  testWidgets(
    'tapping a cluster opens the reel over those stories, oldest first',
    (t) async {
      final h = TabHarness([selfRow])
        ..places = [
          storyPlaceRow('new', created: '2026-10-16T10:00:00Z'),
          storyPlaceRow('old', created: '2026-10-01T10:00:00Z'),
        ];
      await h.pump(t);
      h.view.tapStories(['new', 'old']);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final reel = t.widget<StoryReelScreen>(find.byType(StoryReelScreen));
      expect(reel.placeItems!.map((i) => i.id), ['old', 'new']);
    },
  );

  testWidgets('the list sheet shows story places by day and opens them', (
    t,
  ) async {
    final h = TabHarness([selfRow])
      ..places = [storyPlaceRow('s1', created: '2026-10-16T10:00:00Z')];
    await h.pump(t);
    await t.tap(find.byTooltip('List'));
    await t.pumpAndSettle();
    expect(find.text('Near Osu, Accra'), findsOneWidget);
  });

  testWidgets('recentre includes the visible story pins (spec §3.1)', (
    t,
  ) async {
    final h = TabHarness([selfRow])
      ..places = [storyPlaceRow('s1', lat: 6.5, lng: 3.3)];
    await h.pump(t);
    await t.tap(find.byTooltip('Recentre on us'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits.last.$1.length, 2); // my area + one story
  });

  testWidgets('Mine with no own pins keeps the Stories button (no dead end)', (
    t,
  ) async {
    final h = TabHarness([selfRow])
      ..places = [storyPlaceRow('s1', author: 'kofi')];
    await h.pump(t);
    await t.tap(find.byTooltip('Stories: both of you'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Stories: mine'), findsOneWidget);
    expect(h.view.controller.stories.last.$1, isEmpty);
  });

  testWidgets(
    'cycling the filter back never re-signs thumbnails it already has',
    (t) async {
      final h = TabHarness([selfRow])
        ..places = [
          storyPlaceRow('s1', author: 'kofi'),
          storyPlaceRow('s2', author: 'ama'),
        ];
      final reads = h.reads;
      reads.sign = (key) => 'https://signed/$key';
      await h.pump(t);
      expect(reads.signed, hasLength(2));
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byTooltip(RegExp('Stories:')));
        await t.pumpAndSettle();
      }
      expect(
        reads.signed,
        hasLength(2),
        reason: 'renderer cache by thumbnail key is consulted first',
      );
    },
  );
  testWidgets('a partner who appears later is brought into view once', (
    t,
  ) async {
    final h = TabHarness([selfRow]);
    await h.pump(t);
    expect(h.view.controller.fits, hasLength(1));
    h.rows = [selfRow, partnerRow()];
    ProviderScope.containerOf(
      t.element(find.byType(CoupleMapTab)),
    ).invalidate(coupleMapPresenceProvider('r1'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits, hasLength(2));
    expect(h.view.controller.fits.last.$1, hasLength(2));
    // A later refresh with the same people doesn't move the camera again.
    ProviderScope.containerOf(
      t.element(find.byType(CoupleMapTab)),
    ).invalidate(coupleMapPresenceProvider('r1'));
    await t.pumpAndSettle();
    expect(h.view.controller.fits, hasLength(2));
  });

  testWidgets('a theme flip redraws story pins too (fills follow the theme)', (
    t,
  ) async {
    final h = TabHarness([selfRow])..places = [storyPlaceRow('s1')];
    await h.pump(t);
    final before = h.view.controller.stories.length;
    h.themeMode = ThemeMode.dark;
    await h.repump(t);
    expect(h.view.controller.stories.length, greaterThan(before));
  });

  testWidgets(
    'the compass sits under the right-hand column (with and without Stories)',
    (t) async {
      final h = TabHarness([selfRow]);
      await h.pump(t);
      expect(
        h.view.builtOrnamentTop,
        CoupleMapConfig.rightColumnBottom(stories: false),
      );
      final h2 = TabHarness([selfRow])..places = [storyPlaceRow('s1')];
      await t.pumpWidget(const SizedBox());
      await h2.pump(t);
      expect(
        h2.view.builtOrnamentTop,
        CoupleMapConfig.rightColumnBottom(stories: true),
      );
    },
  );

  // Stories Wave 3: the shell keeps the map mounted behind the privacy
  // cover, so its minute tick must stop itself while nobody can see it.
  testWidgets('the minute tick stops while Attune is covered and picks up '
      'again, with a redraw, when it is on screen', (t) async {
    final h = TabHarness([selfRow, partnerRow()]);
    await h.pump(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump();
    final hidden = h.view.built;
    await t.pump(const Duration(minutes: 3));
    expect(h.view.built, hidden, reason: 'no tick while covered');
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    final back = h.view.built;
    expect(back, greaterThan(hidden), reason: 'redrawn on return');
    await t.pump(const Duration(minutes: 1));
    expect(h.view.built, greaterThan(back), reason: 'ticking again');
  });
}
