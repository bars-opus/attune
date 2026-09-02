// lib/features/games/this_or_that/presentation/screens/question_screen.dart

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/scale_pop.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:attune/core/ui/presence/breathing_dots.dart';

class QuestionScreen extends ConsumerStatefulWidget {
  final String roundId;
  final String questionText;
  final String optionA;
  final String optionB;
  final String? emojiA;
  final String? emojiB;
  final int roundNumber;
  final int totalRounds;
  final String tone;
  final bool isPartnerA;
  final bool isCustom;
  final VoidCallback? onAnswerSubmitted;

  const QuestionScreen({
    super.key,
    required this.roundId,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    this.emojiA,
    this.emojiB,
    required this.roundNumber,
    required this.totalRounds,
    required this.tone,
    required this.isPartnerA,
    this.isCustom = false,
    this.onAnswerSubmitted,
  });

  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen> {
  String? _selectedChoice;
  bool _isSubmitting = false;
  bool _partnerAnswered = false;
  StreamSubscription<GameRound>? _roundSubscription;

  @override
  void initState() {
    super.initState();
    _checkPartnerStatus();
  }

  void _checkPartnerStatus() {
    _roundSubscription = ref
        .read(thisOrThatRepositoryProvider)
        .watchRound(widget.roundId)
        .listen((round) {
          if (!mounted) return;
          setState(() {
            _partnerAnswered =
                widget.isPartnerA
                    ? round.hasUserBAnswered
                    : round.hasUserAAnswered;
          });
        });
  }

  @override
  void dispose() {
    _roundSubscription?.cancel();
    super.dispose();
  }

  Future<void> _submitAnswer() async {
    if (_selectedChoice == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(
        submitAnswerProvider((
          roundId: widget.roundId,
          choice: _selectedChoice!,
          isPartnerA: widget.isPartnerA,
        )).future,
      );

      if (mounted) {
        widget.onAnswerSubmitted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save answer. Tap to retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'This or That • Round ${widget.roundNumber}/${widget.totalRounds}',
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            // Progress and tone.
            //
            // roundNumber and totalRounds were passed in and never shown,
            // so a ten-round game gave no sense of movement -- every
            // round looked identical to the last. The bar is the
            // difference between "how long is this" and a game you can
            // feel yourself getting through.
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm.w,
                    vertical: Spacing.xs.h,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.sm.r,
                    ),
                  ),
                  child: Text(
                    widget.tone.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.roundNumber} of ${widget.totalRounds}',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Gap(Spacing.sm.h),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value:
                    widget.totalRounds == 0
                        ? 0
                        : widget.roundNumber / widget.totalRounds,
                minHeight: 4.h,
                backgroundColor: colorScheme.primary.withOpacity(0.10),
              ),
            ),
            Gap(Spacing.xl.h),
            // Question
            Text(
              widget.questionText,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            // Two cards
            Row(
              children: [
                Expanded(
                  child: _buildChoiceCard(
                    text: widget.optionA,
                    emoji: widget.emojiA,
                    isSelected: _selectedChoice == 'a',
                    onTap: () => _selectChoice('a'),
                    textTheme: textTheme,
                    isWarm: true,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: _buildChoiceCard(
                    text: widget.optionB,
                    emoji: widget.emojiB,
                    isSelected: _selectedChoice == 'b',
                    onTap: () => _selectChoice('b'),
                    textTheme: textTheme,
                    isWarm: false,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Submit button
            AppButton(
              label: 'Submit answer',
              onPressed: _selectedChoice != null ? _submitAnswer : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
            Gap(Spacing.md.h),
            // Partner status.
            //
            // The most emotionally live fact on the screen -- are they
            // here with me right now -- was a grey caption under a
            // button. Waiting now breathes, using the same dots the
            // typing indicator uses, so the wait reads as someone being
            // there rather than as static text.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_partnerAnswered)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 16.h,
                    color: colorScheme.primary,
                  )
                else
                  BreathingDots(
                    size: 5,
                    color: colorScheme.onSurface.withOpacity(0.35),
                  ),
                Gap(Spacing.sm.w),
                Text(
                  _partnerAnswered
                      ? 'They\'ve answered'
                      : 'Waiting for them',
                  style: textTheme.bodySmall?.copyWith(
                    color:
                        _partnerAnswered
                            ? colorScheme.primary
                            : colorScheme.onSurface.withOpacity(0.5),
                    fontWeight:
                        _partnerAnswered ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectChoice(String choice) {
    if (_selectedChoice == choice) return;
    // Tactile + audible confirmation the instant a choice lands.
    ref.read(hapticsProvider).selection();
    ref.read(soundServiceProvider).play(AppSound.gameTap);
    setState(() => _selectedChoice = choice);
  }

  /// The two sides of a choice, tinted differently.
  ///
  /// Both cards used the same neutral surface until one was picked, so a
  /// game about contrast opened as two identical grey boxes. A warm side
  /// and a cool one make the choice look like a choice before anything is
  /// tapped -- and the tints are held at low opacity so the SELECTED
  /// state, which uses the primary colour and a border, still reads as
  /// clearly different from merely being the warm one.
  static const _warmTint = Color(0xFFFF8A65);
  static const _coolTint = Color(0xFF4FC3F7);

  Widget _buildChoiceCard({
    required String text,
    required String? emoji,
    required bool isSelected,
    required VoidCallback onTap,
    required TextTheme textTheme,
    required bool isWarm,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tint = isWarm ? _warmTint : _coolTint;

    // ScalePop gives the picked card a quick confirming "pop"; the trigger is
    // the selection state so it fires only on (de)select, reduce-motion safe.
    return ScalePop(
      trigger: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(Spacing.lg.w),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? colorScheme.primary.withOpacity(0.12)
                    : tint.withOpacity(0.10),
            borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
            border: Border.all(
              color: isSelected ? colorScheme.primary : Colors.transparent,
              width: BorderWidthTokens.md,
            ),
          ),
          child: Column(
            children: [
              if (emoji != null)
                Text(emoji, style: const TextStyle(fontSize: 48)),
              Gap(Spacing.md.h),
              Text(
                text,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
