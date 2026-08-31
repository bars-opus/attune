import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The day label for a chat date separator, Telegram-style.
///
/// Today and Yesterday are named rather than dated; the rest of the last
/// week reads as a weekday, which is more useful than a number for
/// something the reader probably remembers. Older than that becomes a
/// date, gaining a year once it is no longer the current one.
///
/// Compared by LOCAL DAY, never by elapsed hours: 23:59 yesterday is half
/// an hour ago but is still Yesterday.
String chatDateLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final thatDay = DateTime(date.year, date.month, date.day);
  final thisDay = DateTime(today.year, today.month, today.day);
  final daysApart = thisDay.difference(thatDay).inDays;

  if (daysApart == 0) return 'Today';
  if (daysApart == 1) return 'Yesterday';
  if (daysApart < 7) return DateFormat('EEEE').format(date);
  if (date.year == today.year) return DateFormat('d MMMM').format(date);
  return DateFormat('d MMMM y').format(date);
}

/// The floating pill that names the day a run of messages belongs to.
///
/// Used twice: inline between days in the list, and pinned over the top of
/// it while scrolling. One widget so the two can never drift apart
/// visually — the pinned one is meant to look like the inline one has
/// simply stuck to the top.
class ChatDateChip extends StatelessWidget {
  const ChatDateChip({super.key, required this.label, this.opacity = 1});

  final String label;

  /// The pinned chip fades rather than unmounting, so it does not jump
  /// position when it returns.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.smMd,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          // Translucent dark, the way Telegram's chip sits over whatever
          // wallpaper is behind it, rather than a themed surface that
          // would disappear against some of them.
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// The inline date separator: a rule running to both screen edges with the
/// day's label sitting on it.
///
/// Distinct from [ChatDateChip], which is what floats at the top while
/// scrolling. The rule suits an inline separator — it divides one day's
/// messages from the next — and would be wrong on the pinned chip, where a
/// line to both edges reads as cutting the conversation in half rather
/// than labelling a scroll position.
class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final rule = Expanded(
      child: Container(
        key: const ValueKey('chat-date-rule'),
        height: 1,
        // Matched to the chip's own translucent-dark treatment rather than
        // a theme divider, for the same reason: it sits over an arbitrary
        // wallpaper, not a known surface.
        color: Colors.black.withValues(alpha: 0.12),
      ),
    );

    return Row(
      children: [
        rule,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.smMd),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.black.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        rule,
      ],
    );
  }
}
