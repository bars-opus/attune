import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The payoff: their prompt, and what they said to it.
///
/// The one screen in the game where you learn something, so the answer
/// arrives rather than simply being present -- it rises and fades in a
/// beat after the prompt, which is the difference between reading a
/// record and being told something.
class TruthOrDareRoundResultScreen extends ConsumerStatefulWidget {
  const TruthOrDareRoundResultScreen({
    super.key,
    required this.questionType,
    required this.questionText,
    required this.partnerName,
    required this.answerText,
    required this.roundNumber,
    required this.totalRounds,
    required this.onNext,
    this.tone,
  });

  final String questionType;
  final String questionText;
  final String partnerName;
  final String? answerText;
  final int roundNumber;
  final int totalRounds;
  final VoidCallback onNext;
  final String? tone;

  @override
  ConsumerState<TruthOrDareRoundResultScreen> createState() =>
      _TruthOrDareRoundResultScreenState();
}

class _TruthOrDareRoundResultScreenState
    extends ConsumerState<TruthOrDareRoundResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
    if (!_announced) {
      _announced = true;
      // Their answer landing is the beat worth marking -- the one moment
      // in the game where something is actually revealed.
      ref.read(soundServiceProvider).play(AppSound.gameReveal);
      ref.read(hapticsProvider).light();
    }
  }

  bool _announced = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TruthOrDarePalette.of(context, tone: widget.tone);
    final textTheme = Theme.of(context).textTheme;
    final isTruth = widget.questionType == 'truth';
    final accent = palette.accentFor(widget.questionType);
    final answer = widget.answerText?.trim();
    final hasAnswer = answer != null && answer.isNotEmpty;

    // A dare stores the literal string 'completed', which is bookkeeping
    // rather than something anyone said. Showing it as their answer would
    // be a lie about what happened.
    final didDare = !isTruth && answer == 'completed';

    return TruthOrDareScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      tone: widget.tone,
      scrollable: true,
      bottom: TruthOrDarePrimaryAction(
        label:
            widget.roundNumber >= widget.totalRounds
                ? 'See how it went'
                : 'Next round',
        kind: widget.questionType,
        icon: Icons.arrow_forward_rounded,
        onPressed: widget.onNext,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TruthOrDarePromptCard(
            kind: widget.questionType,
            prompt: widget.questionText,
            compact: true,
          ),
          Gap(Spacing.lg.h),
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: const Interval(0.25, 1, curve: Curves.easeOut),
            ),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
                ),
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.lg.w),
                decoration: BoxDecoration(
                  color: palette.panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: palette.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TruthOrDareStageLabel(
                      text: widget.partnerName,
                      icon:
                          didDare
                              ? Icons.check_circle_rounded
                              : Icons.format_quote_rounded,
                      color: accent,
                    ),
                    Gap(Spacing.md.h),
                    Text(
                      didDare
                          ? 'They did it.'
                          : hasAnswer
                          ? answer
                          : 'They kept this one to themselves.',
                      style: textTheme.titleLarge?.copyWith(
                        color:
                            hasAnswer || didDare
                                ? palette.ink
                                : palette.mutedInk,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        fontStyle:
                            hasAnswer || didDare
                                ? FontStyle.normal
                                : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
