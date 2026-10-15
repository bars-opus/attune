import 'dart:io';

import 'package:attune/features/together/domain/together_agenda.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Conversations screen has the Together card, not the old timeline row', () {
    final src =
        File(
          'lib/features/chat/presentation/screens/conversations_screen.dart',
        ).readAsStringSync();
    expect(src, contains('TogetherCard('));
    expect(src, isNot(contains('class _NextCalendarEventRow')));
  });

  test(
    'nextTogetherItem picks the soonest upcoming plan, skipping past times and moments',
    () {
      final now = DateTime(2026, 11, 2, 12);
      TogetherItem i(
        String id,
        DateTime day, {
        DateTime? at,
        TogetherItemKind kind = TogetherItemKind.event,
      }) => TogetherItem(
        kind: kind,
        id: id,
        date: day,
        startsAt: at,
        allDay: at == null,
        title: id,
        participantIds: const ['a'],
      );
      final next = nextTogetherItem([
        i('earlier', DateTime(2026, 11, 2), at: DateTime(2026, 11, 2, 9)),
        i('moment', DateTime(2026, 11, 2), kind: TogetherItemKind.moment),
        i('tonight', DateTime(2026, 11, 2), at: DateTime(2026, 11, 2, 19)),
        i('friday', DateTime(2026, 11, 6)),
      ], now);
      expect(next?.id, 'tonight');
    },
  );
}
