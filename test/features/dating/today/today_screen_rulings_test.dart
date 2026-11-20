// Spec 2 W5b Task 7 rulings (Today as Tasks 4 and 6 left the server and
// the data layer): a paused person reads a calm paused line, never the
// error or Try again (Task 4 M-8); every refusal code Today and act can
// send has its own copy; a photo that fails to sign leaves its own slot
// (positions), and a missing caption is normal (no placeholder); a photo
// failure never reads Today again, and a fresh Today read gives an empty
// slot another try; the photos leave memory when the last Dating page
// closes (§3.4), not when one Dating page replaces another.
import 'dart:async';

import 'package:attune/features/dating/routes/dating_page_watch.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

Future<void> tap(WidgetTester t, Finder finder) async {
  await tapInReach(t, finder);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

/// The photo page whose spoken label is exactly [label].
Finder photoPage(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

void main() {
  final loc = AppLocalizationsEn();

  setUp(() async {
    datingFetched.clear();
    await DatingPhotoMemory.clear();
  });

  Future<DatingShell> open(WidgetTester t, FakeDatingToday fake) =>
      pumpDatingShell(
        t,
        initial: DatingPaths.today,
        overrides: datingTodayOverrides(fake),
      );

  group('refusals', () {
    testWidgets('paused: the calm paused line, settings, no Try again', (
      t,
    ) async {
      await open(t, FakeDatingToday(today: {'ok': false, 'reason': 'paused'}));
      expect(find.text(loc.dating_sectionPaused), findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
      expect(find.text(loc.dating_tryAgain), findsNothing);
      await tap(t, find.text(loc.dating_settingsTitle));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_sectionPaused), findsNothing);
    });

    testWidgets('Today: not_eligible calm; unavailable the error and Retry', (
      t,
    ) async {
      await open(
        t,
        FakeDatingToday(today: {'ok': false, 'reason': 'not_eligible'}),
      );
      expect(find.text(loc.dating_sectionUnavailable), findsOneWidget);
      expect(find.text(loc.dating_errorGeneric), findsNothing);
      await open(
        t,
        FakeDatingToday(today: {'ok': false, 'reason': 'unavailable'}),
      );
      expect(find.text(loc.dating_errorGeneric), findsOneWidget);
      expect(find.text(loc.dating_tryAgain), findsOneWidget);
    });

    testWidgets('act: each refusal code has its own line', (t) async {
      for (final (reason, line) in [
        ('rate_limited', loc.dating_errorRateLimited),
        ('not_eligible', loc.dating_sectionUnavailable),
        ('reverify_device', loc.dating_sectionReverify),
        ('invalid', loc.dating_errorGeneric),
      ]) {
        final fake =
            FakeDatingToday()
              ..answer =
                  (id, action) => DatingActAnswer(ok: false, reason: reason);
        await open(t, fake);
        await tap(t, find.text(loc.dating_cardInterested));
        expect(find.text(line), findsOneWidget, reason: reason);
      }
    });
  });

  group('photos and captions', () {
    testWidgets('a photo that fails to sign leaves its own slot', (t) async {
      final handle = t.ensureSemantics();
      // Photo 1 couldn't be signed: only position 2 comes back.
      final fake =
          FakeDatingToday()
            ..urls = const [DatingPhotoUrl(2, 'https://s.test/2')];
      await open(t, fake);
      expect(datingFetched, ['https://s.test/2']);
      final first = photoPage('Photo 1 of 2. At the beach in Busua');
      expect(first, findsOneWidget);
      expect(
        find.descendant(of: first, matching: find.byType(Image)),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('a missing caption is normal: no placeholder, no gap', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('c', {
              'photos': [
                // The caption the server left off: absent, or null.
                {'id': 'c-p1', 'position': 1},
                {'id': 'c-p2', 'position': 2, 'caption': null},
              ],
            }),
          ],
        }),
      );
      await open(t, fake);
      final first = photoPage('Photo 1 of 2');
      expect(first, findsOneWidget);
      expect(
        find.descendant(of: first, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'Photo 1 of 2\.')), findsNothing);
      handle.dispose();
    });

    testWidgets('a photo failure never reads Today again', (t) async {
      final fake = FakeDatingToday()..urls = null;
      await open(t, fake);
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
      expect(fake.reads, 1);
      expect(fake.photoCalls, [('introduction', 'i1')]);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a fresh Today read gives an empty slot another try', (
      t,
    ) async {
      final fake =
          FakeDatingToday()
            ..urls = null
            ..answer =
                (id, action) =>
                    DatingActAnswer(ok: true, action: action, matched: true);
      await open(t, fake);
      expect(fake.photoCalls, hasLength(1));
      fake.urls = const [
        DatingPhotoUrl(1, 'https://s.test/1'),
        DatingPhotoUrl(2, 'https://s.test/2'),
      ];
      // A match reads Today again.
      await tap(t, find.text(loc.dating_cardInterested));
      await t.pumpAndSettle();
      expect(fake.reads, 2);
      expect(fake.photoCalls, hasLength(2));
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('re-reads', () {
    testWidgets('a re-read keeps the day on screen until it lands', (t) async {
      final fake =
          FakeDatingToday()
            ..answer =
                (id, action) =>
                    DatingActAnswer(ok: true, action: action, matched: true);
      await open(t, fake);
      fake.hold = Completer<DatingToday>();
      await tap(t, find.text(loc.dating_cardInterested));
      expect(fake.reads, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(loc.dating_cardNoted('Kofi')), findsOneWidget);
      fake.hold!.complete(DatingToday.fromJson(datingTodayJson()));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_cardNoted('Kofi')), findsOneWidget);
    });
  });

  group('leaving Dating (§3.4)', () {
    testWidgets('the photos leave memory with the last Dating page', (t) async {
      final shell = await open(t, FakeDatingToday());
      expect(DatingPhotoMemory.length, 2);
      expect(DatingPageWatch.open, 1);
      // Another Dating page on top, or in its place: still in Dating.
      shell.router.push(DatingPaths.stepFromToday('meet'));
      await t.pumpAndSettle();
      expect(DatingPhotoMemory.length, 2);
      shell.router.go(DatingPaths.settings);
      await t.pumpAndSettle();
      expect(DatingPageWatch.open, 1);
      expect(DatingPhotoMemory.length, 2);
      shell.router.go('/home');
      await t.pumpAndSettle();
      expect(DatingPageWatch.open, 0);
      expect(DatingPhotoMemory.length, 0);
    });
  });
}
