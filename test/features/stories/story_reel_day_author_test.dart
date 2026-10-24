// 04 #4: each per-author ring on a calendar day opens that author's
// stories only: the partner's at the first one I have not seen, mine at
// my oldest. Until Wave 5 adds p_author_id, the reel filters the day's
// pages itself, so an author whose stories start on a later page still
// opens on them.
import 'dart:async';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/reel_test_kit.dart';

List<StoryItem> _day(List<(String, String, bool)> spec) {
  final base = DateTime.now().toUtc().subtract(const Duration(days: 3));
  return [
    for (var i = 0; i < spec.length; i++)
      kitItem(
        spec[i].$1,
        author: spec[i].$2,
        createdAt: base.add(Duration(minutes: i)),
        viewed: spec[i].$3,
      ),
  ];
}

void main() {
  testWidgets("the partner's ring plays only the partner's stories", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('m2', kitMe, false),
        ('p2', kitPartner, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'p1');
    expect(bars(tester), (index: 0, count: 2));
    await tapRight(tester);
    expect(shownItemId(tester), 'p2');
  });

  testWidgets("the partner's ring opens at the first story I have not seen", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, true),
        ('m1', kitMe, false),
        ('p2', kitPartner, false),
        ('p3', kitPartner, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'p2');
    expect(bars(tester), (index: 1, count: 3));
  });

  testWidgets('my ring opens at my oldest story that day', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('m1', kitMe, true),
        ('m2', kitMe, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'm1');
    expect(bars(tester), (index: 0, count: 2));
  });

  testWidgets(
    "an author whose stories start on a later page still opens on them",
    (tester) async {
      final gateway = ScriptedReelGateway(
        day: _day([
          ('m1', kitMe, false),
          ('m2', kitMe, false),
          ('p1', kitPartner, false),
          ('p2', kitPartner, false),
        ]),
      )..pageSize = 2;
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        dayAuthorId: kitPartner,
        hold: const Duration(seconds: 30),
      );
      await settle(tester);
      expect(shownItemId(tester), 'p1');
    },
  );

  testWidgets("advancing skips pages with none of the author's stories", (
    tester,
  ) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('m1', kitMe, false),
        ('m2', kitMe, false),
        ('m3', kitMe, false),
        ('p2', kitPartner, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'p1');
    await tapRight(tester);
    await settle(tester);
    expect(shownItemId(tester), 'p2');
  });

  // The original Critical bug was an index desync after a delete; the
  // author filter goes through the same id-tracked reconcile path.
  testWidgets('a delete inside my filtered day ring steps to my next story '
      'and never onto the partner', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('m2', kitMe, false),
        ('p2', kitPartner, false),
        ('m3', kitMe, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await tapRight(tester);
    expect(shownItemId(tester), 'm2');
    expect(bars(tester), (index: 1, count: 3));

    await confirmDelete(tester);
    expect(gateway.deleteCalls, ['m2']);
    expect(shownItemId(tester), 'm3');
    expect(bars(tester), (index: 1, count: 2));

    await confirmDelete(tester);
    expect(gateway.deleteCalls, ['m2', 'm3']);
    expect(shownItemId(tester), 'm1');
    expect(bars(tester), (index: 0, count: 1));
  });

  testWidgets("a partner's delete under their filtered ring keeps the story "
      'on screen by id', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('m1', kitMe, false),
        ('p2', kitPartner, false),
        ('p3', kitPartner, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    await tapRight(tester);
    expect(shownItemId(tester), 'p2');

    gateway.day.removeWhere((i) => i.id == 'p1');
    gateway.emitSignal();
    await settle(tester);
    expect(shownItemId(tester), 'p2');
    expect(bars(tester), (index: 0, count: 2));
  });

  // Fix round 1, I-1: page one of a refreshed day holds none of this
  // author's stories; the reel pages forward instead of closing.
  testWidgets(
    "a signal while the author's stories are past page 1 keeps the story "
    'on screen',
    (tester) async {
      final gateway = ScriptedReelGateway(
        day: _day([
          ('m1', kitMe, false),
          ('m2', kitMe, false),
          ('p1', kitPartner, false),
          ('p2', kitPartner, false),
        ]),
      )..pageSize = 2;
      await pumpReel(
        tester,
        gateway: gateway,
        mode: KitMode.day,
        dayAuthorId: kitPartner,
        hold: const Duration(seconds: 30),
      );
      await settle(tester);
      expect(shownItemId(tester), 'p1');

      gateway.emitSignal();
      await settle(tester);
      await settle(tester);
      expect(find.byType(StoryReelScreen), findsOneWidget);
      expect(shownItemId(tester), 'p1');
      expect(bars(tester), (index: 0, count: 2));

      gateway.day.removeWhere((i) => i.id == 'm1');
      gateway.emitSignal();
      await settle(tester);
      await settle(tester);
      expect(shownItemId(tester), 'p1');
      // p2 is on page two again; the next tap pages to it.
      await tapRight(tester);
      await settle(tester);
      expect(shownItemId(tester), 'p2');
    },
  );

  // Fix round 1, M-1: a failed page while looking for the author's stories
  // says so, with Retry, never "No stories to show."
  testWidgets("a failed page while finding the author's stories offers "
      'Retry', (tester) async {
    final gateway =
        ScriptedReelGateway(
            day: _day([
              ('m1', kitMe, false),
              ('m2', kitMe, false),
              ('p1', kitPartner, false),
            ]),
          )
          ..pageSize = 2
          ..nextPageGate = Completer<void>();
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    gateway.nextListError = StateError('offline');
    gateway.nextPageGate!.complete();
    await settle(tester);
    await settle(tester);
    expect(find.text('No stories to show.'), findsNothing);
    expect(
      find.byKey(const ValueKey('story-reel-error-retry')),
      findsOneWidget,
    );

    gateway.nextPageGate = null;
    await tester.tap(find.byKey(const ValueKey('story-reel-error-retry')));
    await settle(tester);
    await settle(tester);
    expect(shownItemId(tester), 'p1');
  });

  // Fix round 1, M-5.
  testWidgets("deleting the author's last story closes the filtered reel, "
      "though the partner's stories remain", (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
      ]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    expect(shownItemId(tester), 'm1');
    await confirmDelete(tester);
    await tester.pumpAndSettle();
    expect(gateway.deleteCalls, ['m1']);
    expect(find.byType(StoryReelScreen), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  // Wave 4 carry (B5): a delete while the filtered reel pages forward to
  // the story on screen steps off it at once, never after the page fetch.
  testWidgets('a delete while the filtered reel pages forward steps off '
      'the story at once', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
        ('m1', kitMe, false),
        ('m2', kitMe, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');

    // A signal restarts the day at page one; the reel seeks page two,
    // which is held.
    gateway.nextPageGate = Completer<void>();
    gateway.emitSignal();
    await settle(tester);
    await settle(tester);
    expect(shownItemId(tester), 'm1');

    await confirmDelete(tester);
    expect(gateway.deleteCalls, ['m1']);
    expect(shownItemId(tester), 'm2');
    expect(bars(tester), (index: 0, count: 1));

    gateway.nextPageGate!.complete();
    gateway.nextPageGate = null;
    await settle(tester);
    await settle(tester);
    expect(find.byType(StoryReelScreen), findsOneWidget);
    expect(shownItemId(tester), 'm2');
    expect(gateway.deleteCalls, ['m1']);
  });

  testWidgets('a delete of the only story shown while the filtered reel '
      'pages forward closes it at once', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
        ('m1', kitMe, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');

    gateway.nextPageGate = Completer<void>();
    gateway.emitSignal();
    await settle(tester);
    await settle(tester);
    expect(shownItemId(tester), 'm1');

    await confirmDelete(tester);
    await tester.pumpAndSettle();
    expect(gateway.deleteCalls, ['m1']);
    expect(find.byType(StoryReelScreen), findsNothing);
    expect(find.text('HOME'), findsOneWidget);

    gateway.nextPageGate!.complete();
    gateway.nextPageGate = null;
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  // Final review M-1 (probe A): my run of loaded stories ends on the one I
  // delete, and my next story is on the next page.
  testWidgets("deleting the author's last loaded story pages forward to "
      'their next one instead of closing', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
        ('m2', kitMe, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');

    await _deleteAfterTheDialogIsGone(tester, gateway);
    await settle(tester);
    await settle(tester);
    // Long enough for a close's pop to finish.
    await tester.pump(const Duration(seconds: 1));
    expect(gateway.deleteCalls, ['m1']);
    expect(find.byType(StoryReelScreen), findsOneWidget);
    expect(shownItemId(tester), 'm2');
  });

  // Final review M-1 (probe B): the delete steps on to my later story,
  // never back to an earlier one.
  testWidgets("deleting the author's last loaded story steps forward, not "
      'back', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('m2', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
        ('m3', kitMe, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');
    await tapRight(tester);
    expect(shownItemId(tester), 'm2');

    await _deleteAfterTheDialogIsGone(tester, gateway);
    await settle(tester);
    await settle(tester);
    expect(gateway.deleteCalls, ['m2']);
    expect(shownItemId(tester), 'm3');
  });

  // Final review M-1: with nothing later, the delete still closes.
  testWidgets("deleting the author's last story, with only the partner's on "
      'later pages, closes the reel', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
        ('p3', kitPartner, false),
      ]),
    )..pageSize = 2;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');
    await _deleteAfterTheDialogIsGone(tester, gateway);
    await tester.pumpAndSettle();
    expect(gateway.deleteCalls, ['m1']);
    expect(find.byType(StoryReelScreen), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets("a partner's ring asks the server for the partner's stories "
      '(Wave 5)', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
      ]),
    )..serverFiltersAuthor = true;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitPartner,
      hold: const Duration(seconds: 30),
    );
    expect(gateway.dayAuthorIds, isNotEmpty);
    expect(gateway.dayAuthorIds, everyElement(kitPartner));
    expect(shownItemId(tester), 'p1');
    expect(bars(tester), (index: 0, count: 2));
  });

  testWidgets('with the server filtering, deleting the last loaded story '
      'still steps on to the next page (Wave 5)', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('m2', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
        ('m3', kitMe, false),
      ]),
    )
      ..pageSize = 2
      ..serverFiltersAuthor = true;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');
    await tapRight(tester);
    expect(shownItemId(tester), 'm2');

    await _deleteAfterTheDialogIsGone(tester, gateway);
    await settle(tester);
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(gateway.deleteCalls, ['m2']);
    expect(find.byType(StoryReelScreen), findsOneWidget);
    expect(shownItemId(tester), 'm3');
    expect(gateway.dayAuthorIds, everyElement(kitMe));
  });

  testWidgets('with the server filtering, deleting the author\'s only story '
      'closes the reel (Wave 5)', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([
        ('m1', kitMe, false),
        ('p1', kitPartner, false),
        ('p2', kitPartner, false),
      ]),
    )..serverFiltersAuthor = true;
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      dayAuthorId: kitMe,
      hold: const Duration(seconds: 30),
    );
    await settle(tester);
    expect(shownItemId(tester), 'm1');
    expect(bars(tester), (index: 0, count: 1));
    await _deleteAfterTheDialogIsGone(tester, gateway);
    await tester.pumpAndSettle();
    expect(gateway.deleteCalls, ['m1']);
    expect(find.byType(StoryReelScreen), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the whole-day reel asks for the whole day', (tester) async {
    final gateway = ScriptedReelGateway(
      day: _day([('m1', kitMe, false), ('p1', kitPartner, false)]),
    );
    await pumpReel(
      tester,
      gateway: gateway,
      mode: KitMode.day,
      hold: const Duration(seconds: 30),
    );
    expect(gateway.dayAuthorIds, isNotEmpty);
    expect(gateway.dayAuthorIds, everyElement(isNull));
  });
}

/// A delete slower than the confirm dialog's exit, as on a real network:
/// the reel's own route is current again when the delete lands.
Future<void> _deleteAfterTheDialogIsGone(
  WidgetTester tester,
  ScriptedReelGateway gateway,
) async {
  final gate = gateway.deleteGate = Completer<void>();
  await confirmDelete(tester);
  await tester.pump(const Duration(milliseconds: 500));
  gateway.deleteGate = null;
  gate.complete();
  await settle(tester);
}
