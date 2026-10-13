import 'dart:typed_data';

import 'package:attune/features/planning/data/planning_error.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/domain/planning_outbox.dart';
import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_test_app.dart';

const args = (relationshipId: 'r1', entryId: 'e1');

void main() {
  late FakePlanningGateway gateway;
  late FakePlanningMediaGateway media;
  late ProviderContainer c;
  var budgetSpent = 0;
  var lines = <Map<String, dynamic>>[];

  Map<String, dynamic> entryJson() => fakeEntryDetailJson(blocks: [
        fakeBlockJson(id: 'x', type: 'expenses', items: lines),
        {...fakeBlockJson(id: 'bud', type: 'budget', sortKey: 'k'),
          'target_minor': 100000, 'target_currency': 'GHS',
          'computed': {'spent_minor': budgetSpent, 'other_currencies': []}},
        fakeBlockJson(id: 'ph', type: 'photo', sortKey: 'l', payload: {'paths': []}),
        fakeBlockJson(id: 'ln', type: 'link', sortKey: 'm', payload: {'url': 'https://a.example/'}),
      ]);

  Future<PlanningEntryController> ready() async {
    await c.read(planningEntryProvider(args).future);
    return c.read(planningEntryProvider(args).notifier);
  }

  PlanningEntryDetail current() => c.read(planningEntryProvider(args)).requireValue;
  PlanningBlock block(String id) => current().blocks.firstWhere((b) => b.id == id);

  setUp(() {
    budgetSpent = 0;
    lines = [];
    gateway = FakePlanningGateway({'get_planning_entry': (_) => entryJson()});
    media = FakePlanningMediaGateway();
    c = ProviderContainer(overrides: planningOverrides(gateway, store: MemoryOutboxStore(), media: media));
    addTearDown(c.dispose);
    c.listen(planningEntryProvider(args), (_, __) {});
  });

  test('adding an expense line refreshes the server-computed budget', () async {
    final ctl = await ready();
    gateway.handlers['save_planning_rich_item'] = (p) {
      budgetSpent = 2500;
      final line = {...fakeItemJson(id: p['p_id'] as String, text: 'Taxi'), 'amount_minor': 2500, 'currency': 'GHS'};
      lines.add(line);
      return line;
    };
    await ctl.saveRichItem('x', fields: {'label': 'Taxi', 'amount_minor': 2500, 'currency': 'GHS', 'paid_by': 'u-a'});
    expect(block('x').items.single.amountMinor, 2500);
    expect(block('bud').budget!.spentMinor, 2500, reason: 'spent is computed by the server');
    final sent = gateway.callsTo('save_planning_rich_item').single;
    expect(sent['p_version'], isNull);
  });

  test('a stale rich-item edit adopts the partner\'s row and rethrows', () async {
    gateway.handlers['get_planning_entry'] = (_) => fakeEntryDetailJson(blocks: [
          fakeBlockJson(id: 'x', type: 'expenses', items: [
            {...fakeItemJson(id: 'i1', text: 'Taxi'), 'amount_minor': 2500, 'currency': 'GHS'},
          ]),
        ]);
    c.invalidate(planningEntryProvider(args)); // setUp already read the default plan
    final ctl = await ready();
    gateway.handlers['save_planning_rich_item'] = (_) => throw PostgrestException(
        message: 'planning:stale_version', code: 'P0001',
        hint: '{"current":{"id":"i1","sort_key":"V","text":"Taxi home","version":4,"amount_minor":3000,"currency":"GHS"}}');
    await expectLater(
        ctl.saveRichItem('x', existing: block('x').items.single, fields: {'label': 'Taxi', 'amount_minor': 2600}),
        throwsA(isA<PlanningStaleVersion>()));
    expect(block('x').items.single.text, 'Taxi home');
    expect(block('x').items.single.amountMinor, 3000);
  });

  test('photos upload into the couple\'s folder, then attach by that path', () async {
    final ctl = await ready();
    gateway.handlers['add_planning_photo'] =
        (p) => fakeBlockJson(id: 'ph', type: 'photo', payload: {'paths': [p['p_path']]}, version: 2);
    await ctl.addPhoto('ph', Uint8List.fromList([0xFF, 0xD8, 0xFF]));
    final path = media.uploads.single.$1;
    expect(path, matches(RegExp(r'^r1/e1/[0-9a-f-]{36}\.jpg$')));
    expect(gateway.callsTo('add_planning_photo').single, {'p_block_id': 'ph', 'p_path': path});
    expect(block('ph').photoPaths, [path]);
  });

  test('a link asks for its preview when added, when its url changes, and when its preview never came; not otherwise',
      () async {
    final ctl = await ready();
    gateway.handlers['add_planning_block'] = (p) =>
        fakeBlockJson(id: p['p_id'] as String, type: 'link', sortKey: 'z', payload: p['p_payload'] as Map<String, dynamic>);
    final added = await ctl.addBlock(PlanningBlockType.link, payload: {'url': 'https://b.example/'});
    expect(media.previewRequests, [added.id]);

    gateway.handlers['update_planning_block'] = (p) => fakeBlockJson(
        id: p['p_id'] as String, type: 'link', sortKey: 'm', payload: p['p_payload'] as Map<String, dynamic>, version: 2);
    // 'ln' has no preview yet (say YouTube's failed): saving it again retries.
    await ctl.updateBlockPayload(block('ln'), {'url': 'https://a.example/', 'label': 'Same url'});
    expect(media.previewRequests, [added.id, 'ln']);

    final previewed = PlanningBlock.fromJson(fakeBlockJson(id: 'ln', type: 'link', sortKey: 'm', version: 2, payload: {
      'url': 'https://a.example/',
      'preview': {'status': 'ok', 'host': 'a.example', 'title': 'A'},
    }));
    await ctl.updateBlockPayload(previewed, {'url': 'https://a.example/', 'label': 'Renamed'});
    expect(media.previewRequests, [added.id, 'ln'], reason: 'same url, preview fine: nothing to fetch');
    await ctl.updateBlockPayload(previewed, {'url': 'https://c.example/'});
    expect(media.previewRequests, [added.id, 'ln', 'ln']);
  });

  test('turning split on and settling replace the entry', () async {
    final ctl = await ready();
    final on = {
      ...(fakeEntryDetailJson()['entry'] as Map<String, dynamic>),
      'split': {'settled_at': null, 'balances': []},
    };
    gateway.handlers['set_planning_entry_split'] = (_) => {'entry': on};
    await ctl.setSplit(true);
    expect(current().entry.split, isNotNull);
    gateway.handlers['settle_planning_split'] = (_) => {
          'entry': {...on, 'split': {'settled_at': '2026-10-12T10:00:00Z', 'balances': []}}
        };
    await ctl.settleSplit();
    expect(current().entry.split!.settledAt, isNotNull);
  });

  test('budget target saves through its own RPC', () async {
    final ctl = await ready();
    gateway.handlers['update_planning_block_target'] = (p) => {
          ...fakeBlockJson(id: 'bud', type: 'budget', sortKey: 'k', version: 2),
          'target_minor': p['p_target_minor'], 'target_currency': p['p_currency'],
          'computed': {'spent_minor': 0, 'other_currencies': []},
        };
    await ctl.setTarget(block('bud'), 250000, 'GHS');
    expect(block('bud').targetMinor, 250000);
  });
}
