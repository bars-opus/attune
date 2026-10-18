// Spec §3.5 / checklist 5.6: every control on the couple map's surfaces
// meets the platform guidelines, in light and dark (ThemeData.light/dark —
// the harness's themes, not the app's).
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/camera/story_pin_toggle.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/sharing_chip.dart';
import 'package:attune/features/couple_map/widget/data/couple_widget_sync.dart';
import 'package:attune/features/couple_map/widget/presentation/couple_widget_preview.dart';
import 'package:attune/features/location/presentation/providers/presence_providers.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../location/presence_repository_test.dart'
    show FakePresenceGateway, FakeSampler;
import '../stories/support/fake_story_read_gateway.dart';
import 'support/fakes.dart';
import 'support/tab_harness.dart';
import 'widget/support/memory_widget_store.dart';

Future<void> expectGuidelines(WidgetTester t) async {
  await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(t, meetsGuideline(textContrastGuideline));
  // textContrastGuideline skips nodes with a custom Semantics label (the
  // chip, glass buttons, pill): check every Text box against the pixels.
  await expectLater(
    t,
    meetsGuideline(CustomMinimumContrastGuideline(finder: find.byType(Text))),
  );
}

/// Sheets: the shared BottomSheetHeader's "Done" is a 44 dp target since
/// Spec 5 (below Android's 48 dp guideline), so a sheet checks labels and
/// contrast, and every one of OUR rows explicitly against 48 dp.
Future<void> expectSheetGuidelines(WidgetTester t) async {
  await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
  // Only the sheet's own text: what's behind the scrim is meant to be dim.
  await expectLater(
    t,
    meetsGuideline(
      CustomMinimumContrastGuideline(
        finder: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Text),
        ),
      ),
    ),
  );
  for (final row in t.widgetList<InfoRowWidget>(find.byType(InfoRowWidget))) {
    final size = t.getSize(find.byWidget(row));
    expect(size.height, greaterThanOrEqualTo(48), reason: row.title);
  }
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('the map tab, with stories ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h =
          TabHarness([selfRow, partnerRow()])
            ..themeMode = mode
            ..places = [storyPlaceRow('s1')];
      await h.pump(t);
      await expectGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the sharing sheet ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h = TabHarness([selfRow])..themeMode = mode;
      await h.pump(t);
      await t.tap(find.byType(SharingChip));
      await t.pumpAndSettle();
      await expectSheetGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the sharing sheet with the home-screen row on ($mode)', (
      t,
    ) async {
      final semantics = t.ensureSemantics();
      CoupleWidgetSync.store = MemoryCoupleWidgetStore();
      SharedPreferences.setMockInitialValues({'couple_widget_enabled': true});
      final h = TabHarness([selfRow])..themeMode = mode;
      await h.pump(t);
      await t.tap(find.byType(SharingChip));
      await t.pumpAndSettle();
      // The whole card in view: a line clipped at the sheet's edge would
      // read as low contrast.
      await t.ensureVisible(find.byType(CoupleWidgetPreviewCard));
      await t.pumpAndSettle();
      await expectSheetGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the list sheet ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h =
          TabHarness([selfRow, partnerRow()])
            ..themeMode = mode
            ..places = [storyPlaceRow('s1')];
      await h.pump(t);
      await t.tap(find.byTooltip('List'));
      await t.pumpAndSettle();
      await expectSheetGuidelines(t);
      semantics.dispose();
    });

    testWidgets('the not-sharing card ($mode)', (t) async {
      final semantics = t.ensureSemantics();
      final h = TabHarness(const [])..themeMode = mode;
      await h.pump(t);
      await expectGuidelines(t);
      semantics.dispose();
    });
  }

  for (final state in ['found', 'approximate', 'allowLocation']) {
    testWidgets('the camera pill over a dark viewfinder ($state)', (t) async {
      final semantics = t.ensureSemantics();
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
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            coupleMapEnabledProvider.overrideWith((ref) async => true),
            presenceGatewayProvider.overrideWithValue(
              FakePresenceGateway({'couple_map_presence': (_) => const []}),
            ),
            presenceSamplerProvider.overrideWithValue(FakeSampler()),
            presenceTimezoneProvider.overrideWithValue(
              () async => 'Africa/Accra',
            ),
            coupleMapLocalStoreProvider.overrideWithValue(
              MemoryCoupleMapLocalStore(),
            ),
            storyPlaceResolverProvider.overrideWithValue(resolver),
          ],
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: StoryPinToggle(
                  relationshipId: 'r1',
                  onController: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await expectGuidelines(t);
      semantics.dispose();
    });
  }

  testWidgets('the reel place controls (author)', (t) async {
    final semantics = t.ensureSemantics();
    final item = StoryPlace.fromRow(storyPlaceRow('s1', author: 'ama')).story;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const User(
              id: 'ama',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            ),
          ),
          storyPlacesGatewayProvider.overrideWithValue(
            FakeStoryPlacesGateway(),
          ),
          storyReadGatewayProvider.overrideWithValue(FakeStoryReadGateway()),
        ],
        child: MaterialApp(
          home: StoryReelScreen.forPlaces(relationshipId: 'r1', items: [item]),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('reel controls: one actionable node each, no dead duplicate', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    final item = StoryPlace.fromRow(storyPlaceRow('s1', author: 'ama')).story;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const User(
              id: 'ama',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-01-01',
            ),
          ),
          storyPlacesGatewayProvider.overrideWithValue(
            FakeStoryPlacesGateway(),
          ),
          storyReadGatewayProvider.overrideWithValue(FakeStoryReadGateway()),
        ],
        child: MaterialApp(
          home: StoryReelScreen.forPlaces(relationshipId: 'r1', items: [item]),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    final nodes = <SemanticsNode>[];
    void walk(SemanticsNode n) {
      nodes.add(n);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    for (final name in [
      'Close story',
      'Delete this story',
      'Remove from map',
    ]) {
      final named = [
        for (final n in nodes)
          if (n.getSemanticsData().label == name ||
              n.getSemanticsData().tooltip == name)
            n,
      ];
      expect(named, hasLength(1), reason: name);
      expect(
        named.single.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: name,
      );
    }
    semantics.dispose();
  });
}
