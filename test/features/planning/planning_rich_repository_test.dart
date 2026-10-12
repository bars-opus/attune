import 'package:attune/features/planning/data/planning_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';

void main() {
  late FakePlanningGateway gateway;
  late PlanningRepository repo;

  setUp(() {
    gateway = FakePlanningGateway();
    repo = PlanningRepository(gateway);
  });

  test('saveRichItem sends fields and the version (null on create)', () async {
    gateway.handlers['save_planning_rich_item'] = (p) => fakeItemJson(id: p['p_id'] as String);
    await repo.saveRichItem(id: 'i1', blockId: 'b1', fields: {'label': 'Villa', 'amount_minor': 1001}, afterId: 'i0');
    await repo.saveRichItem(id: 'i1', blockId: 'b1', version: 2, fields: {'label': 'Villa'});
    expect(gateway.callsTo('save_planning_rich_item'), [
      {'p_id': 'i1', 'p_block_id': 'b1', 'p_version': null, 'p_fields': {'label': 'Villa', 'amount_minor': 1001}, 'p_after_id': 'i0'},
      {'p_id': 'i1', 'p_block_id': 'b1', 'p_version': 2, 'p_fields': {'label': 'Villa'}, 'p_after_id': null},
    ]);
  });

  test('budget target, split, settle and photos call their RPCs', () async {
    final entry = fakeEntryDetailJson()['entry'];
    gateway.handlers.addAll({
      'update_planning_block_target': (p) => fakeBlockJson(id: p['p_id'] as String, type: 'budget'),
      'set_planning_entry_split': (_) => {'entry': entry},
      'settle_planning_split': (_) => {'entry': entry},
      'add_planning_photo': (p) => fakeBlockJson(id: p['p_block_id'] as String, type: 'photo'),
      'remove_planning_photo': (p) => fakeBlockJson(id: p['p_block_id'] as String, type: 'photo'),
    });
    await repo.updateBlockTarget(id: 'b1', version: 3, targetMinor: 50000, currency: 'USD');
    await repo.setEntrySplit('e1', enabled: true);
    await repo.settleSplit('e1');
    await repo.addPhoto('b2', 'r1/e1/a.jpg');
    await repo.removePhoto('b2', 'r1/e1/a.jpg');
    expect(gateway.callsTo('update_planning_block_target').single,
        {'p_id': 'b1', 'p_version': 3, 'p_target_minor': 50000, 'p_currency': 'USD'});
    expect(gateway.callsTo('set_planning_entry_split').single, {'p_entry_id': 'e1', 'p_enabled': true});
    expect(gateway.callsTo('settle_planning_split').single, {'p_entry_id': 'e1'});
    expect(gateway.callsTo('add_planning_photo').single, {'p_block_id': 'b2', 'p_path': 'r1/e1/a.jpg'});
    expect(gateway.callsTo('remove_planning_photo').single, {'p_block_id': 'b2', 'p_path': 'r1/e1/a.jpg'});
  });
}
