// lib/features/games/truth_or_dare/presentation/screens/partner_watching_screen.dart

import 'dart:async';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
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
      builder:
          (dialogContext) => AlertDialog(
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
    final palette = TruthOrDarePalette.of(context, tone: widget.tone);
    final textTheme = Theme.of(context).textTheme;
    final isDare = widget.questionType == 'dare';
    final accent = palette.accentFor(widget.questionType);

    return TruthOrDareScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      tone: widget.tone,
      scrollable: true,
      // A wait on a partner has no timeout, so there must always be a way
      // out that is not the system back gesture. Losing this was caught
      // by waiting_screens_exit_test, which exists for exactly that.
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _confirmExit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TruthOrDareStageLabel(
            text: "${widget.partnerName}'s turn",
            icon: Icons.hourglass_empty_rounded,
            color: accent,
          ),
          Gap(Spacing.lg.h),
          TruthOrDarePromptCard(
            kind: widget.questionType,
            prompt: widget.content,
          ),
          Gap(Spacing.xl.h),
          Center(child: TruthOrDareWaitingMark(color: accent)),
          Gap(Spacing.md.h),
          Text(
            isDare
                ? '${widget.partnerName} is doing it.'
                : '${widget.partnerName} is thinking.',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            // No countdown and no nudge: this is a person, not a loader,
            // and pressure is the opposite of what this game is for.
            'No rush. You will see it here when they are done.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
          ),
        ],
      ),
    );
  }
}
