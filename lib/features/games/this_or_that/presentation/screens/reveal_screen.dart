// lib/features/games/this_or_that/presentation/screens/reveal_screen.dart
import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/match_indicator.dart';
import 'package:flutter/services.dart' show HapticFeedback;

class RevealScreen extends StatefulWidget {
  final String questionText;
  final String userChoice;
  final String userChoiceText;
  final String userChoiceEmoji;
  final String partnerChoice;
  final String partnerChoiceText;
  final String partnerChoiceEmoji;
  final String partnerName;
  final int roundNumber;
  final int totalRounds;
  final bool isMatch;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final bool hasPrevious;

  const RevealScreen({
    super.key,
    required this.questionText,
    required this.userChoice,
    required this.userChoiceText,
    required this.userChoiceEmoji,
    required this.partnerChoice,
    required this.partnerChoiceText,
    required this.partnerChoiceEmoji,
    required this.partnerName,
    required this.roundNumber,
    required this.totalRounds,
    required this.isMatch,
    required this.onNext,
    this.onPrevious,
    this.hasPrevious = false,
  });

  @override
  State<RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends State<RevealScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _leftSlideAnimation;
  late Animation<Offset> _rightSlideAnimation;
  late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _leftSlideAnimation = Tween<Offset>(
      begin: const Offset(-0.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _rightSlideAnimation = Tween<Offset>(
      begin: const Offset(0.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _flashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: const Interval(0.5, 0.7, curve: Curves.easeOut),
      ),
    );

    _slideController.forward();

    // Celebratory tactile punch the moment a match is revealed — the game's
    // warmest beat. Fired once on entry; a non-match stays silent.
    if (widget.isMatch) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
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
            // Question
            Text(
              widget.questionText,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            // Two columns
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User's choice (left, slides in from left)
                Expanded(
                  child: AnimatedBuilder(
                    animation: _slideController,
                    builder: (context, child) {
                      return SlideTransition(
                        position: _leftSlideAnimation,
                        child: child,
                      );
                    },
                    child: _buildChoiceCard(
                      label: 'You chose',
                      text: widget.userChoiceText,
                      emoji: widget.userChoiceEmoji,
                      isUser: true,
                    ),
                  ),
                ),
                Gap(Spacing.md.w),
                // Partner's choice (right, slides in from right)
                Expanded(
                  child: AnimatedBuilder(
                    animation: _slideController,
                    builder: (context, child) {
                      return SlideTransition(
                        position: _rightSlideAnimation,
                        child: child,
                      );
                    },
                    child: _buildChoiceCard(
                      label: '${widget.partnerName} chose',
                      text: widget.partnerChoiceText,
                      emoji: widget.partnerChoiceEmoji,
                      isUser: false,
                    ),
                  ),
                ),
              ],
            ),
            Gap(Spacing.lg.h),
            // Match indicator — a match settles into a soft celebratory glow
            // on top of its own flash; a non-match renders without the glow.
            GlowPulse(
              active: widget.isMatch,
              child: MatchIndicator(
                isMatch: widget.isMatch,
                animation: _flashAnimation,
              ),
            ),
            const Spacer(),
            // Navigation buttons
            Row(
              children: [
                if (widget.hasPrevious)
                  Expanded(
                    child: AppButton(
                      label: 'Previous',
                      onPressed: widget.onPrevious,
                      size: ButtonSize.medium,
                      customColor: colorScheme.surfaceContainerHighest,
                      textColor: colorScheme.onSurface,
                    ),
                  ),
                if (widget.hasPrevious) Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label:
                        widget.roundNumber == widget.totalRounds
                            ? 'Finish'
                            : 'Next →',
                    onPressed: widget.onNext,
                    size: ButtonSize.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
    required String label,
    required String text,
    required String emoji,
    required bool isUser,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color:
            isUser
                ? colorScheme.primary.withOpacity(0.05)
                : colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        border: Border.all(
          color:
              isUser
                  ? colorScheme.primary.withOpacity(0.3)
                  : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color:
                  isUser
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          Gap(Spacing.md.h),
          if (emoji.isNotEmpty)
            Text(emoji, style: const TextStyle(fontSize: 48)),
          Gap(Spacing.sm.h),
          Text(
            text,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
