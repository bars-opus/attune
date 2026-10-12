import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/data/planning_repository.dart';
import 'package:attune/features/planning/presentation/planning_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';

void main() {
  test('P4 block types round-trip their wire names', () {
    for (final (wire, type) in [
      ('date_poll', PlanningBlockType.datePoll),
      ('countdown', PlanningBlockType.countdown),
      ('progress', PlanningBlockType.progress),
      ('dual_clock', PlanningBlockType.dualClock),
    ]) {
      expect(planningBlockTypeFromWire(wire), type);
      expect(planningBlockTypeToWire(type), wire);
    }
  });

  test('poll votes, countdown target and progress read from the server shape', () {
    final poll = PlanningBlock.fromJson(fakeBlockJson(id: 'p', type: 'date_poll', items: [
      {...fakeItemJson(id: 'o1'), 'date_start': '2026-11-20', 'date_end': '2026-11-25', 'votes': ['u-a', 'u-b']},
    ]));
    expect(poll.items.single.votes, ['u-a', 'u-b']);
    expect(poll.items.single.dateStart, DateTime(2026, 11, 20));

    final cd = PlanningBlock.fromJson({...fakeBlockJson(id: 'c', type: 'countdown'), 'computed': {'target_date': '2026-11-20'}});
    expect(cd.countdownTarget, DateTime(2026, 11, 20));
    expect(PlanningBlock.fromJson({...fakeBlockJson(id: 'c', type: 'countdown'), 'computed': {'target_date': null}}).countdownTarget,
        isNull);

    final numeric = PlanningBlock.fromJson({
      ...fakeBlockJson(id: 'n', type: 'progress', payload: {'mode': 'numeric', 'unit': 'money'}),
      'target_minor': 100000, 'target_currency': 'GHS', 'computed': {'mode': 'numeric', 'current': 60000},
    });
    expect(numeric.progress!.fraction, closeTo(0.6, 1e-9));
    expect(numeric.progress!.isMoney, isTrue);

    final list = PlanningBlock.fromJson({
      ...fakeBlockJson(id: 'l', type: 'progress', payload: {'mode': 'checklist'}),
      'computed': {'mode': 'checklist', 'done': 2, 'total': 2},
    });
    expect(list.progress!.isComplete, isTrue);
    final empty = PlanningBlock.fromJson({
      ...fakeBlockJson(id: 'e', type: 'progress', payload: {'mode': 'checklist'}),
      'computed': {'mode': 'checklist', 'done': 0, 'total': 0},
    });
    expect(empty.progress!.isComplete, isFalse, reason: 'an empty checklist is not a finished goal');
  });

  test('a push for a plan names its relationship and plan, or nothing', () {
    expect(planningEntryTarget({'type': 'planning_entry', 'relationship_id': 'r1', 'entry_id': 'e1'}),
        (relationshipId: 'r1', entryId: 'e1'));
    expect(planningEntryTarget({'type': 'planning_entry', 'entry_id': 'e1'}), isNull);
    expect(planningEntryTarget({'type': 'planning_entry', 'relationship_id': 'r1', 'entry_id': ''}), isNull);
  });

  test('poll, gallery, time zone RPCs', () async {
    final entry = fakeEntryDetailJson();
    final g = FakePlanningGateway({
      'vote_planning_poll': (p) => fakeBlockJson(id: 'p', type: 'date_poll'),
      'lock_planning_poll': (p) => fakeBlockJson(id: 'p', type: 'date', dateStart: '2026-11-20'),
      'set_planning_timezone': (p) => {'timezone': p['p_timezone']},
      'list_planning_gallery': (_) => [
            {'key': 'next_visit', 'name': 'Next visit', 'icon': 'plane', 'color': 'indigo',
             'description': 'Long distance', 'block_types': ['countdown', 'date_poll']},
          ],
      'create_planning_category_from_gallery': (p) => fakeCategoryJson(id: p['p_id'] as String, name: 'Next visit'),
      'planning_timezone_offset_minutes': (p) => 480,
    });
    final repo = PlanningRepository(g);
    await repo.votePoll('o1', vote: true);
    final locked = await repo.lockPoll('p', 'o1');
    await repo.setTimezone('r1', 'Africa/Accra');
    final gallery = await repo.listGallery();
    await repo.createCategoryFromGallery(id: 'c9', relationshipId: 'r1', key: 'next_visit');
    expect(await repo.timezoneOffsetMinutes('Asia/Makassar'), 480);
    expect(locked.type, PlanningBlockType.date);
    expect(gallery.single.name, 'Next visit');
    expect(g.callsTo('vote_planning_poll').single, {'p_item_id': 'o1', 'p_vote': true});
    expect(g.callsTo('lock_planning_poll').single, {'p_block_id': 'p', 'p_item_id': 'o1'});
    expect(g.callsTo('set_planning_timezone').single, {'p_relationship_id': 'r1', 'p_timezone': 'Africa/Accra'});
    expect(g.callsTo('create_planning_category_from_gallery').single,
        {'p_id': 'c9', 'p_relationship_id': 'r1', 'p_gallery_key': 'next_visit'});
    expect(entry, isNotNull);
  });
}
