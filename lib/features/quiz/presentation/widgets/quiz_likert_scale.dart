import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The 1-N rating row shared by every quiz.
///
/// Extracted so the collapsed card and the expanded detail view render the
/// exact same control — a user who taps a value, expands the card, and taps
/// again must be operating one input, not two that happen to look alike.
class QuizLikertScale extends ConsumerWidget {
  const QuizLikertScale({
    super.key,
    required this.value,
    required this.onChanged,
    this.points = 5,
  });

  /// Currently selected point, or null when the question is untouched. Null is
  /// meaningful: it is what stops an unanswered question being advanced past.
  final int? value;
  final ValueChanged<int> onChanged;

  /// Number of scale points. Onboarding's attachment set uses 5; the spec'd
  /// instruments in lib/features/quiz use 7.
  final int points;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<int>(
      segments: [
        for (var i = 1; i <= points; i++)
          ButtonSegment(value: i, label: Text('$i')),
      ],
      emptySelectionAllowed: true,
      selected: value != null ? {value!} : const <int>{},
      onSelectionChanged: (values) {
        if (values.isEmpty) return;
        ref.read(hapticsProvider).selection();
        onChanged(values.first);
      },
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(Size(20.w, 28.h)),
        textStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
        ),
        padding: WidgetStateProperty.all(
          EdgeInsets.symmetric(horizontal: 2.w),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        elevation: WidgetStateProperty.all(0),
      ),
    );
  }
}

/// The legend under the scale, e.g. "1 = No, not really, 5 = Yes,
/// definitely". Defaults avoid "agree/disagree" wording — for a first-person
/// statement, disagree-with-1 reads as a double negative that is easy to
/// misread under a rating scale. Prompts are phrased as direct yes/no
/// questions ("Do you...?", "Can you...?", "Does...?"), so a yes/no-shaped
/// scale maps onto every prompt regardless of what it asks about — unlike
/// "easy/difficult" wording, which only fits ease-of-doing prompts and breaks
/// on frequency ("Do you worry...") or belief ("Do you believe...") ones.
class QuizScaleLegend extends StatelessWidget {
  const QuizScaleLegend({
    super.key,
    this.points = 5,
    this.lowLabel = 'No, not really',
    this.highLabel = 'Yes, definitely',
  });

  final int points;
  final String lowLabel;
  final String highLabel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Text(
        '1 = $lowLabel, \n$points = $highLabel',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.start,
      ),
    );
  }
}
