// lib/features/games/truth_or_dare/presentation/screens/truth_or_dare_end_screen.dart
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TruthOrDareEndScreen extends ConsumerStatefulWidget {
  final int userTruths;
  final int userDares;
  final int partnerTruths;
  final int partnerDares;
  final Map<String, dynamic> mostInterestingPick;
  final VoidCallback onPlayAgain;
  final VoidCallback onTryAnotherGame;

  /// Session tone, so the end screen keeps the board's colour rather than
  /// dropping back to a neutral one at the moment worth remembering.
  final String? tone;

  /// Names, because "Partner" is nobody.
  final String? partnerName;

  const TruthOrDareEndScreen({
    super.key,
    required this.userTruths,
    required this.userDares,
    required this.partnerTruths,
    required this.partnerDares,
    required this.mostInterestingPick,
    required this.onPlayAgain,
    required this.onTryAnotherGame,
    this.tone,
    this.partnerName,
  });

  @override
  ConsumerState<TruthOrDareEndScreen> createState() =>
      _TruthOrDareEndScreenState();
}

class _TruthOrDareEndScreenState extends ConsumerState<TruthOrDareEndScreen> {
  bool _announced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;
    // The game finishing deserves a sound. It was silent here, which made
    // the end of a session feel like a screen you had wandered onto.
    ref.read(soundServiceProvider).play(AppSound.gameComplete);
    ref.read(hapticsProvider).medium();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TruthOrDarePalette.of(context, tone: widget.tone);
    final textTheme = Theme.of(context).textTheme;
    final them = widget.partnerName ?? 'Them';
    final pickText = widget.mostInterestingPick['text']?.toString().trim();
    final pickAnswer = widget.mostInterestingPick['answer']?.toString().trim();

    return TruthOrDareScaffold(
      title: 'That was the game',
      tone: widget.tone,
      scrollable: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TruthOrDarePrimaryAction(
            label: 'Play again',
            icon: Icons.replay_rounded,
            onPressed: widget.onPlayAgain,
          ),
          Gap(Spacing.sm.h),
          TextButton(
            onPressed: widget.onTryAnotherGame,
            style: TextButton.styleFrom(foregroundColor: palette.mutedInk),
            child: const Text('Try a different game'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Counts, not scores. Nobody wins Truth or Dare, and a winner
          // would turn a game about being open into one about points.
          Row(
            children: [
              Expanded(
                child: _TallyCard(
                  name: 'You',
                  truths: widget.userTruths,
                  dares: widget.userDares,
                  palette: palette,
                ),
              ),
              Gap(Spacing.md.w),
              Expanded(
                child: _TallyCard(
                  name: them,
                  truths: widget.partnerTruths,
                  dares: widget.partnerDares,
                  palette: palette,
                ),
              ),
            ],
          ),
          if (pickText != null && pickText.isNotEmpty) ...[
            Gap(Spacing.xl.h),
            TruthOrDareStageLabel(
              text: 'the one that stayed with us',
              color: palette.toneAccent,
            ),
            Gap(Spacing.md.h),
            Container(
              padding: EdgeInsets.all(Spacing.lg.w),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickText,
                    style: textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  if (pickAnswer != null && pickAnswer.isNotEmpty) ...[
                    Gap(Spacing.md.h),
                    Text(
                      pickAnswer,
                      style: textTheme.bodyLarge?.copyWith(
                        color: palette.mutedInk,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One partner's tally of truths and dares.
class _TallyCard extends StatelessWidget {
  const _TallyCard({
    required this.name,
    required this.truths,
    required this.dares,
    required this.palette,
  });

  final String name;
  final int truths;
  final int dares;
  final TruthOrDarePalette palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: textTheme.titleSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          Gap(Spacing.md.h),
          _tallyRow(context, 'Truths', truths, palette.truth),
          Gap(Spacing.xs.h),
          _tallyRow(context, 'Dares', dares, palette.dare),
        ],
      ),
    );
  }

  Widget _tallyRow(
    BuildContext context,
    String label,
    int count,
    Color accent,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        Gap(Spacing.sm.w),
        Expanded(
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
          ),
        ),
        // Counts up rather than appearing. A tally that ticks reads as a
        // result being totted up; one that is simply there reads as a
        // number that was always going to be that.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: count.toDouble()),
          duration:
              reduceMotionOf(context)
                  ? Duration.zero
                  : Duration(milliseconds: 420 + (count * 110)),
          curve: Curves.easeOutCubic,
          builder:
              (context, value, _) => Text(
                '${value.round()}',
                style: textTheme.titleMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ),
      ],
    );
  }
}
