// lib/features/games/this_or_that/presentation/screens/waiting_screen.dart

import 'dart:async';
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WaitingScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String roundId;
  final String questionText;
  final String userChoice;
  final String userChoiceText;
  final String userChoiceEmoji;
  final int roundNumber;
  final int totalRounds;
  final bool isPartnerA;
  final VoidCallback? onRoundUpdated;

  const WaitingScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.questionText,
    required this.userChoice,
    required this.userChoiceText,
    required this.userChoiceEmoji,
    required this.roundNumber,
    required this.totalRounds,
    required this.isPartnerA,
    this.onRoundUpdated,
  });

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen> {
  Timer? _reminderTimer;
  bool _showRemindButton = false;
  bool _isSendingReminder = false;
  late final StreamSubscription _roundSubscription;

  @override
  void initState() {
    super.initState();
    // Start timer for remind button (2 hours = 7200000 ms)
    // For testing, use 10 seconds: _reminderTimer = Timer(const Duration(seconds: 10), _enableRemindButton);
    _reminderTimer = Timer(const Duration(hours: 2), _enableRemindButton);

    // Subscribe to round updates to detect when partner answers
    _roundSubscription = ref
        .read(thisOrThatRepositoryProvider)
        .watchRound(widget.roundId)
        .listen((round) {
          if (round.bothAnswered && mounted) {
            widget.onRoundUpdated?.call();
          }
        });
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _roundSubscription.cancel();
    super.dispose();
  }

  void _enableRemindButton() {
    if (mounted) {
      setState(() {
        _showRemindButton = true;
      });
    }
  }

  Future<void> _sendReminder() async {
    if (_isSendingReminder) return;

    setState(() => _isSendingReminder = true);

    try {
      await ref.read(sendReminderProvider(widget.sessionId).future);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reminder sent!')));
        setState(() => _showRemindButton = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reminder. Please try again later.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingReminder = false);
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _showExitConfirmation(),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
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
            // Your choice
            Text('You chose:', style: textTheme.bodyMedium),
            Gap(Spacing.md.h),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.lg.w,
                vertical: Spacing.md.h,
              ),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.userChoiceEmoji.isNotEmpty)
                    Text(
                      widget.userChoiceEmoji,
                      style: const TextStyle(fontSize: 32),
                    ),
                  Gap(Spacing.sm.w),
                  Text(
                    widget.userChoiceText,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),
            // Waiting animation
            Container(
              padding: EdgeInsets.all(Spacing.lg.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1500),
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (value * 0.4),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary.withValues(alpha: 0.2),
                          ),
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Gap(Spacing.md.h),
                  Text('Waiting for partner...', style: textTheme.titleMedium),
                  Gap(Spacing.sm.h),
                  // Continuous breathing presence — signals the wait is live
                  // (the circle above only pulses once). Reduce-motion safe.
                  BreathingDots(color: colorScheme.primary),
                  Gap(Spacing.sm.h),
                  Text(
                    'They will see your answer when they pick.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (_showRemindButton) ...[
              Gap(Spacing.xl.h),
              AppButton(
                label: 'Remind partner',
                onPressed: _sendReminder,
                size: ButtonSize.medium,
                isLoading: _isSendingReminder,
                customColor: colorScheme.surfaceContainerHighest,
                textColor: colorScheme.onSurface,
              ),
              Gap(Spacing.sm.h),
              Text(
                'Your partner hasn\'t answered yet. A reminder will be sent.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit game?'),
            content: const Text(
              'Your progress will be saved. You can continue later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Exit screen
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Exit'),
              ),
            ],
          ),
    );
  }
}
