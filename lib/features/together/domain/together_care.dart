import 'together_item.dart';

/// A care card's moment: before a partner's big day, or after it.
enum CarePhase { before, after }

class CareCard {
  const CareCard({required this.item, required this.phase});
  final TogetherItem item;
  final CarePhase phase;
}

/// My partner's shared big days that deserve a word now (plan 2b R6):
/// from 18:00 the evening before until it starts, and from its end
/// (start + 1h, or 18:00 for all-day) for 24 hours.
List<CareCard> togetherCareCards(
  List<TogetherItem> items, {
  required String? me,
  required DateTime now,
}) {
  final seen = <String>{};
  final cards = <CareCard>[];
  for (final i in items) {
    if (i.kind != TogetherItemKind.event ||
        i.sourceRef['kind'] != 'big_day' ||
        i.visibility != TogetherVisibility.shared ||
        i.createdBy == null ||
        i.createdBy == me ||
        i.sourceRef['continuation'] == true ||
        !seen.add(i.id)) {
      continue;
    }
    final day = i.date;
    final start = i.startsAt ?? DateTime(day.year, day.month, day.day, 9);
    final end =
        i.endsAt ??
        (i.allDay || i.startsAt == null
            ? DateTime(day.year, day.month, day.day, 18)
            : start.add(const Duration(hours: 1)));
    final eveningBefore = DateTime(day.year, day.month, day.day - 1, 18);
    if (!now.isBefore(eveningBefore) &&
        now.isBefore(start) &&
        !(i.allDay && !now.isBefore(DateTime(day.year, day.month, day.day)))) {
      cards.add(CareCard(item: i, phase: CarePhase.before));
    } else if (!now.isBefore(end) &&
        now.isBefore(end.add(const Duration(hours: 24)))) {
      cards.add(CareCard(item: i, phase: CarePhase.after));
    }
  }
  return cards;
}

/// The message chat opens with: fixed, warm, and the partner can edit it.
String careDraft(CareCard c) =>
    c.phase == CarePhase.before
        ? 'Good luck with ${c.item.title}. You’ve got this!'
        : 'How did ${c.item.title} go?';
