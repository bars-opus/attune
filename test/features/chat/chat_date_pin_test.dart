import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
  });

  test('a date separator is rendered between days', () {
    // isFirstOfDay was computed and used only for spacing and the shimmer
    // — nothing ever drew a separator, so a long conversation had no date
    // structure at all.
    // The inline chip must take its label from the MESSAGE's date.
    // A bare contains('chatDateLabel(') passes on the pinned chip's own
    // call, so it would survive the inline one being hardcoded.
    expect(src, contains('ChatDateChip('));
    expect(src, contains('label: chatDateLabel(message.createdAt)'));
  });

  test('the pinned chip tracks the topmost visible day', () {
    // Telegram pins the current day over the list while scrolling. Without
    // a tracked value the chip would either be absent or stuck on whatever
    // day happened to build first.
    expect(
      src,
      contains('_pinnedDateLabel'),
      reason: 'the pinned chip needs the day currently at the top',
    );
  });

  test('the pinned chip fades out when scrolling stops', () {
    // It floats OVER the messages, so leaving it up permanently would
    // cover a bubble the user is trying to read.
    expect(
      src,
      contains('_pinnedDateTimer'),
      reason:
          'the fade is time-based — a scroll-end notification alone never '
          'arrives for a fling that settles without one',
    );
    expect(src, contains('_pinnedDateVisible'));
  });

  test('the pin timer is cancelled on dispose', () {
    // A Timer outliving the State fires setState on an unmounted widget.
    final disposeBody = src.substring(
      src.indexOf('  void dispose() {', src.indexOf('_MessageListState')),
      src.indexOf('super.dispose();', src.indexOf('_MessageListState')),
    );
    expect(disposeBody, contains('_pinnedDateTimer'));
  });

  test('the list carries no horizontal inset, so the rule spans it', () {
    // The 8px used to sit on the LIST, which clipped the separator's rule
    // 8px short of each edge however wide the row asked to be — an
    // OverflowBox could not escape it. The inset moved onto the message
    // rows, which were its only real consumers.
    expect(
      src,
      contains('EdgeInsets.fromLTRB(0, 10, 0, 96)'),
      reason: 'a list-level horizontal inset clips the date rule',
    );
    expect(
      src,
      isNot(contains('EdgeInsets.fromLTRB(8, 10, 8, 96)')),
    );
  });

  test('the separator is given room to isolate one day from the next', () {
    // 12 above and 4 below was tighter than the gap between two ordinary
    // bubbles (12), so a day boundary read as less of a break than a
    // change of sender. Generous and SYMMETRIC: the separator belongs to
    // neither day, so leaning it toward one reads as a heading for that
    // day rather than a division between both.
    final block = src.substring(
      src.indexOf('child: ChatDateSeparator(') - 300,
      src.indexOf('child: ChatDateSeparator('),
    );
    // Deliberately uneven in source so it is EVEN on screen: the row
    // below adds its own 12px top padding, which a symmetric value here
    // would inherit as a 12px lean toward the older day.
    expect(
      block,
      contains('EdgeInsets.only(top: 32, bottom: 20)'),
      reason: 'a day boundary needs more air than a sender change',
    );
  });

  test('the separator is built ABOVE its message, not below', () {
    // reverse: true flips the LIST\'s scroll axis, not the order of
    // children inside a single item. Placing the separator after the row
    // in the Column therefore rendered it BELOW the message — so the first
    // message of a new day appeared above its own "Today" divider, reading
    // as part of yesterday. The second message of the day looked correct,
    // because it is not first-of-day and draws no separator at all.
    // The whole Column, so both children are inside the slice.
    final start = src.indexOf('if (!isFirstOfDay) return row;');
    final block = src.substring(start, src.indexOf('},', start));

    final separatorIndex = block.indexOf('ChatDateSeparator(');
    final rowIndex = block.indexOf('\n                      row,');

    expect(separatorIndex, isNonNegative);
    expect(rowIndex, isNonNegative, reason: 'the row must still be built');
    expect(
      separatorIndex,
      lessThan(rowIndex),
      reason:
          'the separator must come FIRST in the column to render above the '
          'message it labels',
    );
  });
}
