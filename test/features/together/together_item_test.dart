import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  String kind = 'event',
  bool allDay = false,
  String? startsAt = '2026-11-06T19:00:00+00:00',
  List<String> participants = const ['ama', 'kofi'],
  String visibility = 'shared',
}) => {
  'item_kind': kind,
  'item_id': 'i1',
  'item_date': '2026-11-06',
  'starts_at': startsAt,
  'ends_at': null,
  'all_day': allDay,
  'tz': allDay ? null : 'Africa/Accra',
  'title': 'Dinner',
  'participant_ids': participants,
  'owner_id': 'ama',
  'created_by': 'ama',
  'visibility': visibility,
  'status': 'confirmed',
  'source_ref': {'note': 'Book a table'},
};

void main() {
  test('maps a timed event row; times come back in local time', () {
    final item = TogetherItem.fromRow(_row());
    expect(item.kind, TogetherItemKind.event);
    expect(item.startsAt, DateTime.utc(2026, 11, 6, 19).toLocal());
    expect(item.startsAt!.isUtc, isFalse);
    expect(item.visibility, TogetherVisibility.shared);
    expect(item.sourceRef['note'], 'Book a table');
  });

  test('an all-day row groups under its calendar date', () {
    final item = TogetherItem.fromRow(_row(allDay: true, startsAt: null));
    expect(item.day, DateTime(2026, 11, 6));
  });

  test('a timed row groups under the local day it starts', () {
    final item = TogetherItem.fromRow(_row());
    final local = item.startsAt!;
    expect(item.day, DateTime(local.year, local.month, local.day));
  });

  test('kinds and visibility map from the wire', () {
    expect(
      TogetherItem.fromRow(_row(kind: 'planning_item')).kind,
      TogetherItemKind.planningItem,
    );
    expect(
      TogetherItem.fromRow(_row(kind: 'planning_date')).kind,
      TogetherItemKind.planningDate,
    );
    expect(
      TogetherItem.fromRow(_row(visibility: 'busy_only')).visibility,
      TogetherVisibility.busyOnly,
    );
  });

  test('who it is for, from my point of view', () {
    expect(TogetherItem.fromRow(_row()).whoFor('ama'), TogetherWho.us);
    expect(
      TogetherItem.fromRow(_row(participants: ['ama'])).whoFor('ama'),
      TogetherWho.me,
    );
    expect(
      TogetherItem.fromRow(_row(participants: ['kofi'])).whoFor('ama'),
      TogetherWho.partner,
    );
  });

  test(
    'a continuation day of a multi-day timed event groups under its own date',
    () {
      final row =
          _row()
            ..['item_date'] = '2026-11-07'
            ..['source_ref'] = {'continuation': true};
      expect(TogetherItem.fromRow(row).day, DateTime(2026, 11, 7));
    },
  );
}
