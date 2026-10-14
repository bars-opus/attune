import 'package:attune/features/together/domain/together_need.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a proposal row carries its options in local time', () {
    final n = TogetherNeed.fromRow({
      'need_kind': 'proposal',
      'item_id': 'e1',
      'title': 'Dinner',
      'due_date': null,
      'created_by': 'ama',
      'detail': {
        'all_day': false,
        'tz': 'Africa/Accra',
        'proposed_to': 'kofi',
        'expires_at': '2026-11-09T10:00:00+00:00',
        'options': [
          {
            'id': 'o1',
            'position': 1,
            'start_date': null,
            'end_date': null,
            'starts_at': '2026-11-06T19:00:00+00:00',
            'ends_at': '2026-11-06T21:00:00+00:00',
          },
          {
            'id': 'o2',
            'position': 2,
            'start_date': null,
            'end_date': null,
            'starts_at': '2026-11-07T19:00:00+00:00',
            'ends_at': null,
          },
        ],
      },
    });
    expect(n.kind, TogetherNeedKind.proposal);
    expect(n.options.map((o) => o.id), ['o1', 'o2']);
    expect(n.options.first.start, DateTime.utc(2026, 11, 6, 19).toLocal());
    expect(n.options.last.end, isNull);
    expect(n.expiresAt, DateTime.utc(2026, 11, 9, 10).toLocal());
  });

  test('to-dos and polls point at their plan', () {
    final todo = TogetherNeed.fromRow({
      'need_kind': 'unowned_todo',
      'item_id': 'i1',
      'title': 'Book camp',
      'due_date': '2026-11-05',
      'created_by': null,
      'detail': {'entry_id': 'p1', 'entry_title': 'Summer'},
    });
    expect(todo.kind, TogetherNeedKind.unownedTodo);
    expect(todo.dueDate, DateTime(2026, 11, 5));
    expect(todo.entryId, 'p1');
    expect(
      TogetherNeed.fromRow({
        'need_kind': 'poll',
        'item_id': 'b1',
        'title': 'Lisbon',
        'due_date': null,
        'created_by': null,
        'detail': {'entry_id': 'p2'},
      }).kind,
      TogetherNeedKind.poll,
    );
  });

  test('ProposalTime serialises like the server expects', () {
    expect(
      ProposalTime(
        start: DateTime(2026, 11, 14),
        end: DateTime(2026, 11, 15),
      ).toJson(allDay: true),
      {'start_date': '2026-11-14', 'end_date': '2026-11-15'},
    );
    expect(
      ProposalTime(start: DateTime(2026, 11, 6, 19)).toJson(allDay: false),
      {'starts_at': DateTime(2026, 11, 6, 19).toUtc().toIso8601String()},
    );
  });

  test('an option in the wrong mode is skipped, not a crash', () {
    final n = TogetherNeed.fromRow({
      'need_kind': 'proposal',
      'item_id': 'e1',
      'title': 'Dinner',
      'due_date': null,
      'created_by': 'ama',
      'detail': {
        'all_day': false,
        'options': [
          {
            'id': 'bad',
            'position': 1,
            'start_date': '2026-11-06',
            'end_date': null,
            'starts_at': null,
            'ends_at': null,
          },
          {
            'id': 'ok',
            'position': 2,
            'start_date': null,
            'end_date': null,
            'starts_at': '2026-11-07T19:00:00+00:00',
            'ends_at': null,
          },
        ],
      },
    });
    expect(n.options.map((o) => o.id), ['ok']);
  });
}
