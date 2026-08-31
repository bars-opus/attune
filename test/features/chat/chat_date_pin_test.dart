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
}
