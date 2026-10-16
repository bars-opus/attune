import 'dart:io';
// test/features/couple_map/story_pin_toggle_test.dart
import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_controller.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_toggle.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;
import 'support/fakes.dart';

Future<StoryPinController?> _pump(
  WidgetTester t, {
  bool flag = true,
  List<Map<String, Object?>> presence = const [],
  StoryPlaceDraft? place,
  FakeSampler? sampler,
  FakeStoryPlaceResolver? resolver,
  MemoryCoupleMapLocalStore? local,
}) async {
  StoryPinController? got;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        coupleMapEnabledProvider.overrideWith((ref) async => flag),
        presenceGatewayProvider.overrideWithValue(
          FakePresenceGateway({'couple_map_presence': (_) => presence}),
        ),
        presenceSamplerProvider.overrideWithValue(sampler ?? FakeSampler()),
        presenceTimezoneProvider.overrideWithValue(() async => 'Africa/Accra'),
        coupleMapLocalStoreProvider.overrideWithValue(
          local ?? MemoryCoupleMapLocalStore(),
        ),
        storyPlaceResolverProvider.overrideWithValue(
          resolver ?? FakeStoryPlaceResolver(place),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: StoryPinToggle(
            relationshipId: 'r1',
            onController: (c) => got = c,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return got;
}

/// Real Roboto metrics for the width checks: flutter_test's default Ahem
/// font draws square glyphs ~1.7× wider than the phone's, which would make
/// a 320 dp test meaningless.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final loader = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    final f = File('$root/bin/cache/artifacts/material_fonts/Roboto-$w.ttf');
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRoboto);
  testWidgets('flag off: nothing on the camera, no controller', (t) async {
    final c = await _pump(t, flag: false);
    expect(find.text('Pin to our map'), findsNothing);
    expect(c, isNull);
  });

  testWidgets('off by default; turning it on shows the neighbourhood preview', (
    t,
  ) async {
    final c = await _pump(
      t,
      place: const StoryPlaceDraft(
        lat: 5.556,
        lng: -0.197,
        label: 'Near Osu, Accra',
      ),
    );
    expect(find.text('Pin to our map'), findsOneWidget);
    expect(c!.on, isFalse);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Near Osu, Accra'), findsOneWidget);
  });

  testWidgets(
    'paused: "Your area is paused", switch off but still the author\'s to turn on',
    (t) async {
      final c = await _pump(
        t,
        presence: const [
          {'who': 'self', 'freshness': 'fresh', 'my_paused_until': 'infinity'},
        ],
      );
      expect(find.text('Your area is paused'), findsOneWidget);
      expect(c!.on, isFalse);
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    },
  );

  testWidgets(
    'the camera never samples presence (it only reads my state once)',
    (t) async {
      final sampler = FakeSampler();
      await _pump(
        t,
        presence: const [
          {
            'who': 'self',
            'cell_lat': 5.565,
            'cell_lng': -0.208,
            'freshness': 'fresh',
          },
        ],
        sampler: sampler,
      );
      expect(sampler.sampled, 0);
    },
  );

  testWidgets('labelled for screen readers, and never below a 44 dp target', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await _pump(t);
    expect(find.bySemanticsLabel(RegExp('Pin to our map')), findsWidgets);
    expect(
      t.getSize(find.byType(StoryPinToggle)).height,
      greaterThanOrEqualTo(44),
    );
    semantics.dispose();
  });

  testWidgets('no permission: "Allow location…" opens Settings', (t) async {
    final sampler = FakeSampler();
    await _pump(
      t,
      resolver:
          FakeStoryPlaceResolver()..problem = StoryPlaceProblem.noPermission,
      sampler: sampler,
    );
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Allow location for Attune to pin places'));
    await t.pumpAndSettle();
    expect(sampler.openedSettings, 1);
  });

  testWidgets('denied but askable: the line asks again instead of Settings', (
    t,
  ) async {
    final sampler = FakeSampler();
    final local = MemoryCoupleMapLocalStore();
    await writePinLastChoice(local, true);
    final resolver =
        FakeStoryPlaceResolver()..problem = StoryPlaceProblem.needsAsk;
    await _pump(t, resolver: resolver, sampler: sampler, local: local);
    await t.tap(find.text('Allow location for Attune to pin places'));
    await t.pumpAndSettle();
    expect(resolver.asks, [false, true]);
    expect(sampler.openedSettings, 0);
  });

  testWidgets('approximate: the preview says so', (t) async {
    await _pump(
      t,
      resolver: FakeStoryPlaceResolver(
        const StoryPlaceDraft(
          lat: 5.556,
          lng: -0.197,
          label: 'Near Osu, Accra',
        ),
      )..approximate = true,
    );
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Near Osu, Accra · approximate'), findsOneWidget);
  });

  for (final state in ['found', 'approximate', 'allowLocation']) {
    testWidgets(
      'fits a 320 dp screen ($state): no overflow, words readable (Review Focus 5)',
      (t) async {
        t.view.physicalSize = const Size(
          192,
          400,
        ); // between close and flip at 320 dp
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final resolver = FakeStoryPlaceResolver(
          const StoryPlaceDraft(
            lat: 5.556,
            lng: -0.197,
            label: 'Near Osu, Accra',
          ),
        );
        if (state == 'approximate') resolver.approximate = true;
        if (state == 'allowLocation') {
          resolver.problem = StoryPlaceProblem.noPermission;
        }
        await _pump(t, resolver: resolver);
        await t.tap(find.byType(Switch));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(
          find.byIcon(Icons.place_outlined),
          findsNothing,
          reason: 'the icon gives way first',
        );
        for (final p in t.renderObjectList<RenderParagraph>(
          find.byType(Text),
        )) {
          expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
        }
      },
    );
  }

  testWidgets('location services off: "Turn on location…" opens settings', (
    t,
  ) async {
    final sampler = FakeSampler();
    await _pump(
      t,
      resolver:
          FakeStoryPlaceResolver()..problem = StoryPlaceProblem.servicesOff,
      sampler: sampler,
    );
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Allow location for Attune to pin places'), findsNothing);
    await t.tap(find.text('Turn on location to pin places'));
    await t.pumpAndSettle();
    expect(sampler.openedSettings, 1);
  });
}
