import 'dart:async';
import 'dart:typed_data';

import 'package:attune/features/planning/data/planning_media.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/planning_outbox.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:attune/features/planning/presentation/screens/planning_entry_screen.dart';
import 'package:attune/features/planning/presentation/widgets/photo_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../chat/support/chat_test_harness.dart' show withScreenUtil;
import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const _screen = PlanningEntryScreen(relationshipId: 'r1', entryId: 'e1');
const _args = (relationshipId: 'r1', entryId: 'e1');

void main() {
  testWidgets('M1: a poll option that could not be removed offers no Undo', (tester) async {
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'poll', type: 'date_poll', items: [
              {...fakeItemJson(id: 'o1'), 'date_start': '2026-11-20', 'votes': []},
            ]),
          ]),
      'delete_planning_block_item': (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001'),
    });
    await tester.pumpWidget(planningTestApp(g, _screen));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Nov 20, 2026'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Dates removed'), findsNothing);
    expect(find.text('That was removed by your partner.'), findsOneWidget);
  });

  test('M3: photo links live 10 minutes and are re-signed before they expire', () {
    expect(SupabasePlanningMediaGateway.signedUrlTtl, const Duration(minutes: 10));
    expect(planningSignedUrlReuse < SupabasePlanningMediaGateway.signedUrlTtl, isTrue);
  });

  testWidgets('M8: a photo picked as the plan closes still attaches, without an error', (tester) async {
    final picked = Completer<PlanningPickedPhotos>();
    final g = FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [fakeBlockJson(id: 'ph', type: 'photo', payload: {'paths': []})]),
      'add_planning_photo': (p) => fakeBlockJson(id: 'ph', type: 'photo', payload: {'paths': [p['p_path']]}, version: 2),
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [...planningOverrides(g), planningPhotoPickerProvider.overrideWithValue((_, __) => picked.future)],
      child: withScreenUtil(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _screen)),
            child: const Text('open'),
          ),
        ),
      )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pump(const Duration(milliseconds: 500)); // the busy bar animates while preparing
    await tester.pageBack(); // leave the plan while the photo is being prepared
    await tester.pump(const Duration(seconds: 1));
    picked.complete((photos: [Uint8List.fromList([0xff, 0xd8, 0xff])], rejected: 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(g.callsTo('add_planning_photo'), hasLength(1));
  });

  test('M10: re-reading progress after a tick does not undo a later tick on screen', () async {
    var fetches = 0;
    final g = FakePlanningGateway({
      'get_planning_entry': (_) {
        fetches++;
        // A snapshot taken before the second tick reached the server.
        return fakeEntryDetailJson(blocks: [
          fakeBlockJson(id: 'l', items: [
            fakeItemJson(id: 'i1', checkedAt: fetches > 1 ? '2026-10-12T09:00:00Z' : null, version: fetches > 1 ? 2 : 1),
            fakeItemJson(id: 'i2', text: 'Eggs', sortKey: 'W'),
          ]),
          {...fakeBlockJson(id: 'p', type: 'progress', sortKey: 'k', payload: {'mode': 'checklist'}),
            'computed': {'mode': 'checklist', 'done': fetches > 1 ? 1 : 0, 'total': 2}},
        ]);
      },
      'set_planning_block_item_checked': (p) => fakeItemJson(
          id: p['p_id'] as String, text: p['p_id'] == 'i2' ? 'Eggs' : 'Milk', checkedAt: '2026-10-12T09:00:00Z', version: 2),
    });
    final c = ProviderContainer(overrides: planningOverrides(g, store: MemoryOutboxStore()));
    addTearDown(c.dispose);
    c.listen(planningEntryProvider(_args), (_, __) {});
    await c.read(planningEntryProvider(_args).future);
    final ctl = c.read(planningEntryProvider(_args).notifier);
    PlanningEntryDetail current() => c.read(planningEntryProvider(_args)).requireValue;
    await ctl.setChecked('l', current().blocks.first.items[0], true);
    // The second tick is on screen; its own reply hasn't been applied yet.
    unawaited(ctl.setChecked('l', current().blocks.first.items[1], true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(current().blocks.first.items[1].isChecked, isTrue, reason: 'the refetch must not flicker it back');
    expect(current().blocks.last.progress!.done, 1, reason: 'progress still comes from the server');
  });

  testWidgets('M11: the "Planning unavailable" screen has a way back', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlanningUnavailableScreen())),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Planning unavailable.'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
  });
}


