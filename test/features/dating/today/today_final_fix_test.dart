// Spec 2 W5 final fix wave (final-client-review.md), Today and the moment:
// a match made by this person's own Interested shows its moment even after
// another moment this visit, while a moment from the other side still waits
// for the next visit (M-1); a photo load overtaken by a block writes nothing
// back (M-2); Widen shows nothing of the last account once another signs in
// (M-4); Today holds no photo bytes beyond DatingPhotoMemory's 20 (M-12); a
// match whose name is missing still shows its moment (M-13); and the dark
// and reduce-motion renders (M-14).
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/dating_today_providers.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Map<String, Object?> _moment(String id, Object? name) => {
  'match_id': id,
  'display_name': name,
};

void main() {
  final loc = AppLocalizationsEn();

  setUp(() async {
    datingFetched.clear();
    await DatingPhotoMemory.clear();
    // The shell's app shows the debug banner; the renders here don't.
    WidgetsApp.debugAllowBannerOverride = false;
  });
  tearDown(() => WidgetsApp.debugAllowBannerOverride = true);

  Future<DatingShell> open(
    WidgetTester t,
    FakeDatingToday fake, {
    List<Override> overrides = const [],
    Widget Function(Widget child)? theme,
  }) => pumpDatingShell(
    t,
    initial: DatingPaths.today,
    overrides: [...datingTodayOverrides(fake), ...overrides],
    wrap: theme == null ? null : (_, child) => theme(child),
  );

  group('M-1: the moment of a match made here', () {
    testWidgets('a moment, Later, a moment from the other side waits; then '
        'this person\'s own Interested matches: its moment opens', (t) async {
      final fake = FakeDatingToday(
          today: datingTodayJson({
            'moments': [_moment('m1', 'Yaw')],
          }),
        )
        ..answer =
            (id, action) =>
                DatingActAnswer(ok: true, action: action, matched: true);
      final shell = await open(t, fake);
      expect(find.text(loc.dating_momentTitle('Yaw')), findsOneWidget);
      // m1 is seen; Later goes back to Today, which reads again.
      fake.json = datingTodayJson();
      await tap(t, find.text(loc.dating_momentLater));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      // A moment from the other side keeps "one moment per visit".
      fake.json = datingTodayJson({
        'moments': [_moment('m3', 'Esi')],
      });
      shell.container.invalidate(datingTodayProvider('ama'));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_momentTitle('Esi')), findsNothing);
      expect(find.text(loc.dating_cardInterested), findsOneWidget);
      // Ama's own Interested on Kofi, who said Interested already: the
      // card leaves Today, and the match's moment opens at once.
      fake.json = datingTodayJson({
        'cards': <Object?>[],
        'moments': [_moment('m3', 'Esi'), _moment('m2', 'Kofi')],
      });
      await tap(t, find.text(loc.dating_cardInterested));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_momentTitle('Kofi')), findsOneWidget);
      expect(find.text(loc.dating_momentTitle('Esi')), findsNothing);
      expect(fake.seen, ['m1', 'm2']);
    });
  });

  group('M-2: a block while the photos download', () {
    test('a load overtaken by forget writes nothing back', () async {
      final gate = Completer<void>();
      final fake = FakeDatingToday();
      final load = loadDatingPhotos(
        fake,
        (url) async {
          await gate.future;
          return Uint8List.fromList(datingTestPng);
        },
        'introduction',
        'i1',
        positions: const [1, 2],
      );
      await Future<void>.delayed(Duration.zero);
      DatingPhotoMemory.forget('introduction', 'i1');
      gate.complete();
      final bytes = await load;
      expect(bytes.every((b) => b.isEmpty), isTrue);
      expect(DatingPhotoMemory.length, 0);
      // A load started after the forget writes as usual.
      await loadDatingPhotos(
        fake,
        (url) async => Uint8List.fromList(datingTestPng),
        'introduction',
        'i1',
        positions: const [1, 2],
      );
      expect(DatingPhotoMemory.length, 2);
    });

    testWidgets('Today: blocked mid-download, no photo of the person stays', (
      t,
    ) async {
      final gate = Completer<void>();
      final fake = FakeDatingToday();
      await open(
        t,
        fake,
        overrides: [
          datingPhotoFetchProvider.overrideWithValue((url) async {
            await gate.future;
            return Uint8List.fromList(datingTestPng);
          }),
        ],
      );
      expect(fake.photoCalls, [('introduction', 'i1')]);
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pumpAndSettle();
      await tapInReach(t, find.text(loc.dating_blockRow('Kofi')));
      await t.pumpAndSettle();
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
      gate.complete();
      await t.pumpAndSettle();
      expect(DatingPhotoMemory.length, 0);
      expect(find.byType(Image), findsNothing);
    });
  });

  testWidgets('M-4: Widen shows nothing of the last account and closes', (
    t,
  ) async {
    final fake = FakeDatingToday(
      today: datingTodayJson({'today_state': 'empty', 'cards': <Object?>[]}),
    );
    final shell = await open(t, fake);
    await tap(t, find.text(loc.dating_todayWiden));
    await t.pumpAndSettle();
    final ages = find.text(loc.dating_widenAges(25, 40));
    expect(ages, findsOneWidget);
    shell.container.read(datingTestAccount.notifier).state = 'kwame';
    await t.pump();
    expect(ages, findsNothing);
    expect(
      find.text(loc.dating_widenHowFar(loc.dating_scopeRegion)),
      findsNothing,
    );
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('at ${DatingPaths.stepFromToday('meet')}'), findsNothing);
  });

  // Follow-up ruling on M-12 (re-review I-R1): Today keeps the photos it
  // loaded (at most 9 cards of 6, memory only), so no introduction is ever
  // judged without its photos because the 20-image memory dropped them.
  testWidgets('M-12 follow-up: four cards of six photos all show every '
      'photo, and a fresh read downloads none again', (t) async {
    final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            for (final id in ['i1', 'i2', 'i3', 'i4'])
              datingCardJson(id, {
                'photos': [
                  for (var p = 1; p <= 6; p++)
                    {'id': '$id-p$p', 'position': p, 'caption': null},
                ],
              }),
          ],
        }),
      )
      ..urls = [
        for (var p = 1; p <= 6; p++) DatingPhotoUrl(p, 'https://s.test/$p'),
      ];
    final shell = await open(
      t,
      fake,
      overrides: [
        // Each photo its own bytes, as a real download is.
        datingPhotoFetchProvider.overrideWithValue(
          (url) async => Uint8List.fromList(datingTestPng),
        ),
      ],
    );
    expect(fake.photoCalls, hasLength(4));
    void everySlotShown() {
      final cards =
          t
              .widgetList<DatingCardView>(
                find.byType(DatingCardView, skipOffstage: false),
              )
              .toList();
      expect(cards, hasLength(4));
      for (final v in cards) {
        expect(v.photos, hasLength(6));
        expect(v.photos.first.isNotEmpty, isTrue);
        expect(v.photos.every((b) => b.isNotEmpty), isTrue);
      }
    }

    everySlotShown();
    // The memory itself stays bounded.
    expect(DatingPhotoMemory.length, lessThanOrEqualTo(DatingPhotoMemory.max));
    // A fresh Today read: nothing is downloaded again, nothing goes grey.
    shell.container.invalidate(datingTodayProvider('ama'));
    await t.pumpAndSettle();
    expect(fake.reads, 2);
    expect(fake.photoCalls, hasLength(4));
    everySlotShown();
  });

  group('M-13: a match whose name is missing', () {
    test('JSON null or no name still parses, as no name', () {
      final day = DatingToday.fromJson(
        datingTodayJson({
          'moments': [
            _moment('m1', null),
            {'match_id': 'm2'},
            _moment('m3', 42),
          ],
        }),
      );
      expect(
        [for (final m in day.moments) (m.matchId, m.name)],
        [('m1', ''), ('m2', '')],
      );
    });

    testWidgets('its moment shows, with the no-name copy, and is marked seen', (
      t,
    ) async {
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'moments': [_moment('m1', null)],
        }),
      );
      await open(t, fake);
      expect(find.text(loc.dating_momentTitleNoName), findsOneWidget);
      expect(fake.seen, ['m1']);
    });
  });

  group('M-14: dark and reduce motion', () {
    testWidgets('the moment, dark: golden and guidelines', (t) async {
      await open(
        t,
        FakeDatingToday(
          today: datingTodayJson({
            'my_name': 'Ama',
            'moments': [_moment('m1', 'Kofi')],
          }),
        ),
        theme: (child) => Theme(data: AppTheme.darkTheme, child: child),
      );
      expect(find.text(loc.dating_momentTitle('Kofi')), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/match_moment.dark.png'),
      );
      await expectFlowGuidelines(t);
    });

    testWidgets('the moment under reduce motion: settled in place', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(
        t,
        FakeDatingToday(
          today: datingTodayJson({
            'my_name': 'Ama',
            'moments': [_moment('m1', 'Kofi')],
          }),
        ),
      );
      final avatars = find.byKey(const ValueKey('dating_moment_avatars'));
      expect(
        find.descendant(of: avatars, matching: find.byType(Transform)),
        findsNothing,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/match_moment.reduce.png'),
      );
    });

    testWidgets('Not for me under reduce motion: the card simply goes', (
      t,
    ) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final fake = FakeDatingToday();
      await open(t, fake);
      await tapInReach(t, find.text(loc.dating_cardNotForMe));
      await t.pump();
      // The next frame has no card and no animated wrapper.
      expect(find.text(loc.dating_cardInterested), findsNothing);
      expect(find.byType(AnimatedSize), findsNothing);
      await t.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/today_not_for_me.reduce.png'),
      );
      // The undo window ends: the pass is sent.
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(fake.acts.map((a) => a.$3), ['passed']);
    });
  });
}
