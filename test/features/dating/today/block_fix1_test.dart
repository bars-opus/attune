// Spec 2 W5b Task 7b fix round 1 (task-7b-review.md): a card whose name is
// missing (or only spaces) reads "this person" on More, the confirm and the
// calm line, never "Block ?" (M-1); an ok block takes the person's photos
// out of memory and leaves everyone else's (M-2); the card's answers wait
// while its block is out (M-3); the More sheet's Block row has no "open in
// new" icon, and the sheet has its goldens and guidelines (M-6).
import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/today/dating_photo_memory.dart';
import 'package:attune/features/dating/today/dating_today.dart';
import 'package:attune/features/dating/today/today_screen.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';
import '../support/dating_today_fakes.dart';

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

  String photo(String id, int position) =>
      DatingPhotoMemory.key('introduction', id, position);

  test('forget drops one introduction\'s photos and misses, no other', () {
    final a = Uint8List.fromList([1]);
    final b = Uint8List.fromList([2]);
    final c = Uint8List.fromList([3]);
    final d = Uint8List.fromList([4]);
    DatingPhotoMemory.put(photo('a', 1), a);
    DatingPhotoMemory.put(photo('a', 2), b);
    DatingPhotoMemory.put(photo('ab', 1), c);
    DatingPhotoMemory.put(DatingPhotoMemory.key('match', 'a', 1), d);
    DatingPhotoMemory.missed('introduction', 'a');
    DatingPhotoMemory.missed('introduction', 'a');
    expect(DatingPhotoMemory.mayAsk('introduction', 'a'), isFalse);
    DatingPhotoMemory.forget('introduction', 'a');
    expect(DatingPhotoMemory.get(photo('a', 1)), isNull);
    expect(DatingPhotoMemory.get(photo('a', 2)), isNull);
    expect(DatingPhotoMemory.get(photo('ab', 1)), same(c));
    expect(DatingPhotoMemory.get(DatingPhotoMemory.key('match', 'a', 1)), d);
    expect(DatingPhotoMemory.length, 2);
    expect(DatingPhotoMemory.mayAsk('introduction', 'a'), isTrue);
  });

  testWidgets(
    'M-1: a name of only spaces reads "this person" on More, the confirm '
    'and the calm line',
    (t) async {
      final semantics = t.ensureSemantics();
      final fake = FakeDatingToday(
        today: datingTodayJson({
          'cards': [
            datingCardJson('i1', {'display_name': '  '}),
          ],
        }),
      );
      await open(t, fake);
      expect(find.bySemanticsLabel(loc.dating_cardMoreNoName), findsOneWidget);
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockRowNoName), findsOneWidget);
      await tapInReach(t, find.text(loc.dating_blockRowNoName));
      await t.pumpAndSettle();
      expect(find.text(loc.dating_blockTitleNoName), findsOneWidget);
      expect(find.text(loc.dating_blockBodyNoName), findsOneWidget);
      expect(find.bySemanticsLabel(loc.dating_blockRowNoName), findsOneWidget);
      for (final line in [
        loc.dating_cardMoreNoName,
        loc.dating_blockRowNoName,
        loc.dating_blockTitleNoName,
        loc.dating_blockBodyNoName,
        loc.dating_blockDoneNoName,
      ]) {
        expect(
          RegExp(r'\bthey\b', caseSensitive: false).hasMatch(line),
          isFalse,
          reason: line,
        );
      }
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pumpAndSettle();
      expect(fake.blocks.map((b) => b.$2), ['i1']);
      expect(find.text(loc.dating_blockDoneNoName), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('M-2: an ok block takes that person\'s photos out of memory, and '
      'leaves the next card\'s', (t) async {
    final fake = FakeDatingToday(
      today: datingTodayJson({
        'cards': [
          datingCardJson('i1'),
          datingCardJson('i2', {'display_name': 'Ama'}),
        ],
      }),
    );
    await open(t, fake);
    await t.pumpAndSettle();
    for (final id in ['i1', 'i2']) {
      expect(DatingPhotoMemory.get(photo(id, 1)), isNotNull, reason: id);
      expect(DatingPhotoMemory.get(photo(id, 2)), isNotNull, reason: id);
    }
    await tapInReach(t, find.text(loc.dating_cardMore).first);
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_blockRow('Kofi')));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(loc.dating_cardBlock));
    await t.pumpAndSettle();
    expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
    expect(DatingPhotoMemory.get(photo('i1', 1)), isNull);
    expect(DatingPhotoMemory.get(photo('i1', 2)), isNull);
    expect(DatingPhotoMemory.get(photo('i2', 1)), isNotNull);
    expect(DatingPhotoMemory.get(photo('i2', 2)), isNotNull);
  });

  testWidgets(
    'M-3: while the block is out, the card\'s Interested and Not for me '
    'send nothing',
    (t) async {
      final fake =
          FakeDatingToday()..blockHold = Completer<DatingBlockAnswer>();
      await open(t, fake);
      await tapInReach(t, find.text(loc.dating_cardMore));
      await t.pumpAndSettle();
      await tapInReach(t, find.text(loc.dating_blockRow('Kofi')));
      await t.pumpAndSettle();
      await tapInReach(t, find.text(loc.dating_cardBlock));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(fake.blocks, hasLength(1));
      await tapInReach(t, find.text(loc.dating_cardInterested));
      await t.pump();
      await t.tap(find.text(loc.dating_cardNotForMe), warnIfMissed: false);
      await t.pump();
      await t.pump(const Duration(seconds: 6));
      expect(fake.acts, isEmpty);
      expect(find.text(loc.dating_cardNotForMeDone), findsNothing);
      fake.blockHold!.complete(const DatingBlockAnswer(ok: true));
      await t.pumpAndSettle();
      expect(fake.acts, isEmpty);
      expect(find.text(loc.dating_blockDone('Kofi')), findsOneWidget);
    },
  );

  testWidgets(
    'M-6: the More sheet: Block has no "open in new" icon; goldens and '
    'guidelines',
    (t) async {
      Future<void> openMore(WidgetTester t) async {
        await tapInReach(t, find.text(loc.dating_cardMore));
        await t.pumpAndSettle();
      }

      for (final (variant, scale, direction) in flowGoldenVariants) {
        // A fresh ProviderScope each time (Task 7's golden ruling).
        await t.pumpWidget(const SizedBox());
        await pumpFlowScreen(
          t,
          () => const DatingTodayScreen(),
          textScale: scale,
          direction: direction,
          overrides: [
            ...datingShellOverrides(),
            ...datingTodayOverrides(FakeDatingToday()),
          ],
        );
        await openMore(t);
        expect(find.text(loc.dating_blockRow('Kofi')), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new), findsNothing, reason: variant);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/today_more_sheet.$variant.png'),
        );
        expect(t.takeException(), isNull, reason: variant);
        if (variant == 'scale1.0') await expectFlowGuidelines(t);
      }
    },
  );
}
