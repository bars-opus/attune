import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/widgets/quiz_likert_scale.dart';

/// One quiz question, in two layouts that share a Hero flight.
///
/// **Collapsed** (in the card deck): number badge, prompt, truncated
/// description, then the scale — reading order for someone meeting the
/// question for the first time.
///
/// **Expanded** (tapped): the scale and its legend move to the TOP, followed
/// by the prompt and the full untruncated description. By the time a user
/// opens the detail view they have already read the prompt; what they want is
/// to answer while reading, without the control scrolling off the bottom of a
/// long explanation.
///
/// Both layouts are driven from this one widget so the four quizzes in this
/// feature reuse the same interaction, and so the two states cannot drift
/// apart. Answering works identically in either.
class QuizQuestionCard extends StatefulWidget {
  const QuizQuestionCard({
    super.key,
    required this.questionNumber,
    required this.prompt,
    required this.value,
    required this.onChanged,
    this.description,
    this.points = 5,
    this.lowLabel = 'No, not really',
    this.highLabel = 'Yes, definitely',
    this.collapsedDescriptionLines = 2,
    this.heroTag,
    this.footer,
  });

  /// 1-based, shown in the badge.
  final int questionNumber;
  final String prompt;

  /// Situational explanation. When null the card renders without the
  /// description block and tapping does not expand — there is nothing more to
  /// show, so offering the affordance would be a dead end.
  final String? description;

  final int? value;
  final ValueChanged<int> onChanged;

  final int points;
  final String lowLabel;
  final String highLabel;
  final int collapsedDescriptionLines;

  /// Distinct per question so consecutive cards don't share a flight. Defaults
  /// to the question number, which is unique within a quiz.
  final Object? heroTag;

  /// Actions rendered below the scale in the COLLAPSED layout only (Next /
  /// Back). The expanded view deliberately omits them: advancing from a detail
  /// sheet would leave the user on a card they can no longer see.
  final Widget? footer;

  bool get _isExpandable =>
      description != null && description!.trim().isNotEmpty;

  Object get _tag => heroTag ?? 'quiz-question-$questionNumber';

  @override
  State<QuizQuestionCard> createState() => _QuizQuestionCardState();
}

class _QuizQuestionCardState extends State<QuizQuestionCard> {
  /// True from the moment the detail view is pushed until its POP animation
  /// (including the Hero return flight) has fully finished. The onboarding
  /// deck plays its own Next/Finish transition by swapping this card's content
  /// for a fresh instance while the old one animates away — if that swap
  /// happens while a Hero from this card is still reparented into the
  /// Overlay for an in-flight return animation, the two independent animation
  /// systems can tear down/relayout the same subtree in the same frame
  /// ("RenderBox was not laid out"). Disabling the footer for the round trip
  /// guarantees the flight is fully settled before Next/Finish can fire.
  bool _detailBusy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _NumberBadge(number: widget.questionNumber, tag: widget._tag),
        Gap(Spacing.md.h),
        const AppDivider(),
        Gap(Spacing.md.h),
        _Prompt(prompt: widget.prompt, tag: widget._tag),
        if (widget._isExpandable) ...[
          Gap(Spacing.sm.h),
          InkWell(
            onTap: () => _openDetail(context),
            borderRadius: BorderRadius.circular(8.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DescriptionText(
                  tag: widget._tag,
                  description: widget.description!,
                  maxLines: widget.collapsedDescriptionLines,
                ),
                Gap(Spacing.xs.h),
                Text(
                  'Read more',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
        Gap(Spacing.lg.h),
        QuizLikertScale(
          value: widget.value,
          onChanged: widget.onChanged,
          points: widget.points,
        ),
        Gap(Spacing.sm.h),
        QuizScaleLegend(
          points: widget.points,
          lowLabel: widget.lowLabel,
          highLabel: widget.highLabel,
        ),
        if (widget.footer != null)
          IgnorePointer(ignoring: _detailBusy, child: widget.footer!),
      ],
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    setState(() => _detailBusy = true);
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      // Hero handles the card's flight; the surrounding scrim is what
      // fades. reduceMotion collapses this to an instant cut.
      transitionDuration:
          reduceMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 320),
      reverseTransitionDuration:
          reduceMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 260),
      pageBuilder: (_, animation, __) {
        return FadeTransition(
          opacity: animation,
          child: _QuizQuestionDetail(
            tag: widget._tag,
            questionNumber: widget.questionNumber,
            prompt: widget.prompt,
            description: widget.description!,
            value: widget.value,
            onChanged: widget.onChanged,
            points: widget.points,
            lowLabel: widget.lowLabel,
            highLabel: widget.highLabel,
          ),
        );
      },
    );
    unawaited(Navigator.of(context).push(route));
    // route.completed (NOT the push()'s own future) is what actually waits
    // for the reverse transition to finish. Navigator.push()'s future
    // resolves as soon as pop() is CALLED — Route.didPop() completes it
    // synchronously, before the reverse animation even starts (this is
    // documented on TransitionRoute.completed: "[popped] typically completes
    // before the animation even starts"). Gating on push() alone let Next
    // fire while the Hero return flight was still live, which was the actual
    // race behind the "RenderBox was not laid out" crash — closing the
    // detail view and immediately tapping Next reintroduced the exact
    // collision HeroMode(enabled: false) was meant to prevent, because the
    // Hero hadn't actually finished flying home yet.
    await route.completed;
    if (mounted) setState(() => _detailBusy = false);
  }
}

/// Expanded layout: scale first, then legend, then prompt, then the full
/// description — the reordering that makes the detail view useful rather than
/// just larger.
class _QuizQuestionDetail extends StatefulWidget {
  const _QuizQuestionDetail({
    required this.tag,
    required this.questionNumber,
    required this.prompt,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.points,
    required this.lowLabel,
    required this.highLabel,
  });

  final Object tag;
  final int questionNumber;
  final String prompt;
  final String description;
  final int? value;
  final ValueChanged<int> onChanged;
  final int points;
  final String lowLabel;
  final String highLabel;

  @override
  State<_QuizQuestionDetail> createState() => _QuizQuestionDetailState();
}

class _QuizQuestionDetailState extends State<_QuizQuestionDetail> {
  /// Mirrors the answer locally so the scale updates immediately here. The
  /// parent is notified on every change, so closing the sheet needs no
  /// commit step and dismissing never silently drops a selection.
  late int? _value = widget.value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Column(
            children: [
              Expanded(
                child: CardInkWell(
                  margin: EdgeInsets.only(bottom: 0),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(Spacing.lg.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppTextButton(
                          text: 'Done',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Gap(Spacing.lg.h),
                        Align(
                          alignment: Alignment.center,
                          child: _NumberBadge(
                            number: widget.questionNumber,
                            tag: widget.tag,
                          ),
                        ),
                        Gap(Spacing.lg.h),
                        // Scale first — the whole point of the reorder.
                        Align(
                          alignment: Alignment.center,
                          child: QuizLikertScale(
                            value: _value,
                            points: widget.points,
                            onChanged: (v) {
                              setState(() => _value = v);
                              widget.onChanged(v);
                            },
                          ),
                        ),
                        Gap(Spacing.sm.h),
                        QuizScaleLegend(
                          points: widget.points,
                          lowLabel: widget.lowLabel,
                          highLabel: widget.highLabel,
                        ),
                        Gap(Spacing.lg.h),
                        const AppDivider(),
                        Gap(Spacing.lg.h),
                        _Prompt(prompt: widget.prompt, tag: widget.tag),
                        Gap(Spacing.md.h),
                        _DescriptionText(
                          tag: widget.tag,
                          description: widget.description,
                        ),
                        Gap(Spacing.md.h),
                        Text(
                          _answerHint(),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Prompts are phrased as direct questions ("Do you...?", "Can you...?"),
  /// so this reads naturally as the answer to whatever was just asked without
  /// needing to restate or rephrase the prompt itself.
  String _answerHint() {
    return 'If that\'s a clear yes, pick "${widget.highLabel}". If it\'s a clear no, pick "${widget.lowLabel}". Anywhere in between is fine too — go with whatever\'s closest.';
  }
}

/// Shared between both layouts so it flies rather than cross-fades.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number, required this.tag});

  final int number;
  final Object tag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Hero(
      tag: 'badge-$tag',
      child: Container(
        padding: EdgeInsets.all(Spacing.sm.w),
        decoration: BoxDecoration(
          color: colorScheme.onSurface,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$number',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.surface,
          ),
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.prompt, required this.tag});

  final String prompt;
  final Object tag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Hero(
      tag: 'prompt-$tag',
      // Text inside a Hero needs its own Material during the flight, or it
      // renders with the debug double-underline and no theme.
      flightShuttleBuilder: (_, __, ___, ____, ______) {
        return Material(
          color: Colors.transparent,
          child: Text(
            prompt,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Text(
          prompt,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The situational description, shared between the collapsed (truncated) and
/// expanded (full) layouts via one Hero flight — this is what makes tapping
/// read as the description itself growing into the detail view, rather than
/// a box fading in underneath separately-flying badge/prompt text.
///
/// [maxLines] is collapsed-only; the expanded destination always renders the
/// full text. A Hero interpolates the destination's own layout during flight,
/// so the mid-flight frames already show untruncated text growing into place
/// — no separate shuttle needed to avoid an ellipsis visibly snapping away.
class _DescriptionText extends StatelessWidget {
  const _DescriptionText({
    required this.tag,
    required this.description,
    this.maxLines,
  });

  final Object tag;
  final String description;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Hero(
      tag: 'description-$tag',
      flightShuttleBuilder: (_, __, ___, ____, ______) {
        return Material(
          color: Colors.transparent,
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: Text(
          description,
          style: (maxLines != null
                  ? Theme.of(context).textTheme.bodySmall
                  : Theme.of(context).textTheme.bodyMedium)
              ?.copyWith(color: colorScheme.onSurfaceVariant, height: 1.5),
          maxLines: maxLines,
          overflow: maxLines != null ? TextOverflow.ellipsis : null,
        ),
      ),
    );
  }
}
