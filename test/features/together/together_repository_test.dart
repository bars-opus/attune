import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/couple_event_draft.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_need.dart';
import 'package:attune/features/together/domain/together_ritual.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeTogetherGateway implements TogetherRpcGateway {
  FakeTogetherGateway(this.handlers);
  final Map<String, dynamic Function(Map<String, dynamic>)> handlers;
  final List<(String, Map<String, dynamic>)> calls = [];

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    calls.add((function, params ?? const {}));
    final h = handlers[function];
    if (h == null) throw StateError('no handler for $function');
    return h(params ?? const {});
  }
}

void main() {
  test('listItems sends the range as plain dates and maps rows', () async {
    final g = FakeTogetherGateway({
      'list_together_items':
          (_) => [
            {
              'item_kind': 'moment',
              'item_id': 'm1',
              'item_date': '2026-11-05',
              'starts_at': null,
              'ends_at': null,
              'all_day': true,
              'tz': null,
              'title': 'Beach',
              'participant_ids': ['ama'],
              'owner_id': null,
              'created_by': 'ama',
              'visibility': 'shared',
              'status': 'confirmed',
              'source_ref': {'event_type': 'highlight'},
            },
          ],
    });
    final items = await TogetherRepository(g).listItems(
      'rel-1',
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30, 23),
    );
    expect(g.calls.single.$2, {
      'p_relationship_id': 'rel-1',
      'p_start': '2026-11-01',
      'p_end': '2026-11-30',
    });
    expect(items.single.kind, TogetherItemKind.moment);
  });

  test('createEvent sends the draft payload and returns the new id', () async {
    final g = FakeTogetherGateway({'create_couple_event': (_) => 'ev-1'});
    final draft = CoupleEventDraft(
      title: 'Dinner',
      allDay: true,
      start: DateTime(2026, 11, 7),
      participantIds: const ['ama'],
    );
    expect(await TogetherRepository(g).createEvent('rel-1', draft), 'ev-1');
    expect(g.calls.single.$2['p_relationship_id'], 'rel-1');
    expect(g.calls.single.$2['p_event'], draft.toPayload());
  });

  test('server refusals become TogetherException codes', () async {
    final g = FakeTogetherGateway({
      'delete_couple_event':
          (_) => throw const PostgrestException(message: 'together:not_found'),
    });
    await expectLater(
      TogetherRepository(g).deleteEvent('ev-1'),
      throwsA(
        isA<TogetherException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
  });
  test('proposals, decisions and hand-offs call their RPCs', () async {
    final g = FakeTogetherGateway({
      'propose_couple_event': (_) => 'ev-9',
      'decide_couple_event': (_) => null,
      'propose_owner_handoff': (_) => null,
      'decide_owner_handoff': (_) => null,
      'list_together_needs_you':
          (_) => [
            {
              'need_kind': 'handoff',
              'item_id': 'e1',
              'title': 'Plumber',
              'due_date': '2026-11-10',
              'created_by': 'ama',
              'detail': {'kind': 'event'},
            },
          ],
    });
    final repo = TogetherRepository(g);
    final draft = CoupleEventDraft(
      title: 'Dinner',
      allDay: false,
      start: DateTime(2026, 11, 6, 19),
      timezone: 'UTC',
      participantIds: const ['ama', 'kofi'],
    );
    expect(
      await repo.proposeEvent('r1', draft, [
        ProposalTime(start: DateTime(2026, 11, 6, 19)),
      ]),
      'ev-9',
    );
    expect(
      (g.calls.last.$2['p_options'] as List).single,
      contains('starts_at'),
    );
    await repo.decideProposal('ev-9', optionId: 'o1', accept: true);
    expect(g.calls.last.$2, {
      'p_event_id': 'ev-9',
      'p_option_id': 'o1',
      'p_accept': true,
      'p_note': null,
    });
    await repo.proposeHandoff('e1');
    await repo.decideHandoff('e1', accept: false);
    expect(g.calls.last.$2, {'p_event_id': 'e1', 'p_accept': false});
    expect((await repo.listNeeds('r1')).single.kind, TogetherNeedKind.handoff);
  });
  test(
    'skipping and detaching one occurrence send the date as a plain day',
    () async {
      final g = FakeTogetherGateway({
        'skip_couple_event_occurrence': (_) => null,
        'detach_couple_event_occurrence': (_) => 'ev-2',
      });
      final repo = TogetherRepository(g);
      await repo.skipOccurrence('e1', DateTime(2026, 10, 23, 19));
      expect(g.calls.last.$1, 'skip_couple_event_occurrence');
      expect(g.calls.last.$2, {'p_event_id': 'e1', 'p_on': '2026-10-23'});
      final oneOff = CoupleEventDraft(
        title: 'Date night',
        allDay: false,
        start: DateTime(2026, 10, 30, 20),
        timezone: 'Europe/London',
        participantIds: const ['ama', 'kofi'],
      );
      expect(
        await repo.detachOccurrence('e1', DateTime(2026, 10, 30), oneOff),
        'ev-2',
      );
      expect(g.calls.last.$1, 'detach_couple_event_occurrence');
      expect(g.calls.last.$2, {
        'p_event_id': 'e1',
        'p_on': '2026-10-30',
        'p_event': oneOff.toPayload(),
      });
    },
  );
  test('ritual calls', () async {
    final g = FakeTogetherGateway({
      'list_together_rituals': (_) => const [],
      'propose_ritual': (_) => 'rit-1',
      'decide_ritual': (_) => null,
      'update_ritual': (_) => null,
      'set_ritual_status': (_) => null,
      'skip_ritual_occurrence': (_) => null,
    });
    final repo = TogetherRepository(g);
    const draft = RitualDraft(
      template: 'custom',
      title: 'Walk',
      cadence: RitualCadence.fortnightly,
      weekday: 6,
      hour: 10,
      minute: 30,
      durationMin: 60,
      tz: 'UTC',
    );
    expect(await repo.proposeRitual('r1', draft), 'rit-1');
    await repo.decideRitual('rit-1', accept: true);
    expect(g.calls.last.$2, {'p_ritual_id': 'rit-1', 'p_accept': true});
    await repo.setRitualStatus('rit-1', 'paused');
    expect(g.calls.last.$2, {'p_ritual_id': 'rit-1', 'p_status': 'paused'});
    await repo.skipRitualOccurrence('e1');
    expect(g.calls.last.$2, {'p_event_id': 'e1'});
    expect(await repo.listRituals('r1'), isEmpty);
  });
}
