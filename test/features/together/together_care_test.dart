import 'package:attune/features/together/domain/together_care.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _big({
  String createdBy = 'kofi',
  TogetherVisibility visibility = TogetherVisibility.shared,
  DateTime? start,
  DateTime? end,
  bool allDay = false,
  String kind = 'big_day',
  bool continuation = false,
}) => TogetherItem(
  kind: TogetherItemKind.event,
  id: 'b1',
  date: DateTime(2026, 11, 10),
  startsAt: allDay ? null : (start ?? DateTime(2026, 11, 10, 10)),
  endsAt: allDay ? null : end,
  allDay: allDay,
  title: 'Interview',
  participantIds: [createdBy],
  createdBy: createdBy,
  visibility: visibility,
  sourceRef: {'kind': kind, if (continuation) 'continuation': true},
);

void main() {
  test('the evening before brings a word-of-luck card, until it starts', () {
    expect(
      togetherCareCards(
        [_big()],
        me: 'ama',
        now: DateTime(2026, 11, 9, 17, 59),
      ),
      isEmpty,
    );
    expect(
      togetherCareCards(
        [_big()],
        me: 'ama',
        now: DateTime(2026, 11, 9, 18),
      ).single.phase,
      CarePhase.before,
    );
    expect(
      togetherCareCards(
        [_big()],
        me: 'ama',
        now: DateTime(2026, 11, 10, 9, 59),
      ).single.phase,
      CarePhase.before,
    );
    expect(
      togetherCareCards(
        [_big()],
        me: 'ama',
        now: DateTime(2026, 11, 10, 10, 30),
      ),
      isEmpty,
    );
  });

  test('after it ends, ask how it went for a day', () {
    final item = _big(end: DateTime(2026, 11, 10, 11));
    expect(
      togetherCareCards(
        [item],
        me: 'ama',
        now: DateTime(2026, 11, 10, 11),
      ).single.phase,
      CarePhase.after,
    );
    expect(
      togetherCareCards(
        [item],
        me: 'ama',
        now: DateTime(2026, 11, 11, 10, 59),
      ).single.phase,
      CarePhase.after,
    );
    expect(
      togetherCareCards([item], me: 'ama', now: DateTime(2026, 11, 11, 11, 1)),
      isEmpty,
    );
  });

  test('no end: an hour after it starts; all-day: from 18:00', () {
    expect(
      togetherCareCards(
        [_big()],
        me: 'ama',
        now: DateTime(2026, 11, 10, 11),
      ).single.phase,
      CarePhase.after,
    );
    expect(
      togetherCareCards(
        [_big(allDay: true)],
        me: 'ama',
        now: DateTime(2026, 11, 10, 18),
      ).single.phase,
      CarePhase.after,
    );
    expect(
      togetherCareCards(
        [_big(allDay: true)],
        me: 'ama',
        now: DateTime(2026, 11, 10, 12),
      ),
      isEmpty,
    );
  });

  test("only my partner's shared big days, once each", () {
    final now = DateTime(2026, 11, 9, 20);
    expect(
      togetherCareCards([_big(createdBy: 'ama')], me: 'ama', now: now),
      isEmpty,
    );
    expect(
      togetherCareCards(
        [_big(visibility: TogetherVisibility.busyOnly)],
        me: 'ama',
        now: now,
      ),
      isEmpty,
    );
    expect(
      togetherCareCards([_big(kind: 'event')], me: 'ama', now: now),
      isEmpty,
    );
    expect(
      togetherCareCards(
        [_big(), _big(continuation: true)],
        me: 'ama',
        now: now,
      ),
      hasLength(1),
    );
  });

  test('drafts are fixed, warm and editable', () {
    final before =
        togetherCareCards(
          [_big()],
          me: 'ama',
          now: DateTime(2026, 11, 9, 20),
        ).single;
    expect(careDraft(before), 'Good luck with Interview. You’ve got this!');
    final after =
        togetherCareCards(
          [_big()],
          me: 'ama',
          now: DateTime(2026, 11, 10, 12),
        ).single;
    expect(careDraft(after), 'How did Interview go?');
  });
}
