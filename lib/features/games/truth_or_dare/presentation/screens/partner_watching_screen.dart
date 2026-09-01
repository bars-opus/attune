// lib/features/games/truth_or_dare/presentation/screens/partner_watching_screen.dart

import 'dart:async';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PartnerWatchingScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String roundId;
  final int roundNumber;
  final int totalRounds;
  final String tone;
  final bool isPartnerA;
  final String partnerName;
  final String questionType; // 'truth' or 'dare'
  final String content;
  final bool hasAnswered;

  const PartnerWatchingScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.roundNumber,
    required this.totalRounds,
    required this.tone,
    required this.isPartnerA,
    required this.partnerName,
    required this.questionType,
    required this.content,
    required this.hasAnswered,
  });

  @override
  ConsumerState<PartnerWatchingScreen> createState() =>
      _PartnerWatchingScreenState();
}

class _PartnerWatchingScreenState extends ConsumerState<PartnerWatchingScreen> {
  late final StreamSubscription _roundSubscription;
  bool _partnerCompleted = false;

  @override
  void initState() {
    super.initState();
    _subscribeToRoundUpdates();
  }

  @override
  void dispose() {
    _roundSubscription.cancel();
    super.dispose();
  }

  void _subscribeToRoundUpdates() {
    _roundSubscription = ref
        .read(supabaseClientProvider)
        .from('game_session_rounds')
        .stream(primaryKey: ['id'])
        .eq('id', widget.roundId)
        .listen((event) {
          if (event.isNotEmpty) {
            final data = event.first;
            final bothAnswered = data['both_answered'] as bool? ?? false;

            if (bothAnswered && mounted && !_partnerCompleted) {
              setState(() {
                _partnerCompleted = true;
              });
              _navigateToSessionRouter();
            }
          }
        });
  }

  void _navigateToSessionRouter() {
    context.pushReplacementNamed(
      'truthOrDareSessionRouter',
      extra: widget.sessionId,
    );
  }

  /// Leaves a wait that may last hours.
  ///
  /// Confirmed rather than immediate: the player is mid-game, and a
  /// mis-tap on a close button should not drop them out of it. Mirrors
  /// This or That's waiting screen, which already did this correctly.
  void _confirmExit() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave for now?'),
        content: const Text(
          'Your progress is saved. The game stays in your chat, and you '
          'can pick it up from there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.pop(context);
            },
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final typeIcon = widget.questionType == 'truth' ? '🗣' : '🎯';
    final typeLabel = widget.questionType == 'truth' ? 'TRUTH' : 'DARE';

    return Scaffold(
      appBar: AppBar(
        // Watching a partner's turn could last as long as they take, and
        // this screen had no back button at all: the only way out was to
        // kill the app. Progress is on the server, so leaving costs
        // nothing but the live view.
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _confirmExit,
        ),
        title: Text(
          'Truth or Dare • Round ${widget.roundNumber}/${widget.totalRounds}',
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            Text(
              '${widget.partnerName}\'s turn 👀',
              style: textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            // Type badge
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: Spacing.sm.w,
                vertical: Spacing.xs.h,
              ),
              decoration: BoxDecoration(
                color:
                    widget.questionType == 'truth'
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(typeIcon, style: const TextStyle(fontSize: 16)),
                  Gap(Spacing.xs.w),
                  Text(
                    typeLabel,
                    style: textTheme.labelSmall?.copyWith(
                      color:
                          widget.questionType == 'truth'
                              ? Colors.green
                              : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Gap(Spacing.md.h),
            // Content
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Text(
                widget.content,
                style: textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
            // Waiting animation
            Container(
              padding: EdgeInsets.all(Spacing.lg.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary.withOpacity(0.2),
                          ),
                          child: Center(
                            child: Container(
                              width: 20,
                              height: 20,
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
                  Text(
                    'Waiting for ${widget.partnerName} to complete...',
                    style: textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
