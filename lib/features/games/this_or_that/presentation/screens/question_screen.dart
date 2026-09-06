import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestionScreen extends ConsumerStatefulWidget {
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
    this.partnerName = 'Partner',
    this.isCustom = false,
    this.onAnswerSubmitted,
  });

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
  final String partnerName;
  final bool isCustom;
  final VoidCallback? onAnswerSubmitted;

  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedChoice;
  bool _isSubmitting = false;
  bool _partnerAnswered = false;
  bool _startedEntrance = false;
  StreamSubscription<GameRound>? _roundSubscription;
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    _roundSubscription = ref
        .read(thisOrThatRepositoryProvider)
        .watchRound(widget.roundId)
        .listen((round) {
          if (!mounted) return;
          final answered =
              widget.isPartnerA
                  ? round.hasUserBAnswered
                  : round.hasUserAAnswered;
          if (answered != _partnerAnswered) {
            setState(() => _partnerAnswered = answered);
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startedEntrance) return;
    _startedEntrance = true;
    if (reduceMotionOf(context)) {
      _entranceController.value = 1;
    } else {
      _entranceController.forward();
    }
  }

  @override
  void dispose() {
    _roundSubscription?.cancel();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer() async {
    final selected = _selectedChoice;
    if (selected == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    ref.read(hapticsProvider).medium();

    try {
      await ref.read(
        submitAnswerProvider((
          roundId: widget.roundId,
          choice: selected,
          isPartnerA: widget.isPartnerA,
        )).future,
      );
      if (mounted) widget.onAnswerSubmitted?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your pick was not saved. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _selectChoice(String choice) {
    if (_isSubmitting || _selectedChoice == choice) return;
    ref.read(hapticsProvider).selection();
    ref.read(soundServiceProvider).play(AppSound.gameTap);
    setState(() => _selectedChoice = choice);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final selectedText =
        _selectedChoice == 'a'
            ? widget.optionA
            : _selectedChoice == 'b'
            ? widget.optionB
            : null;

    return ThisOrThatGameScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThisOrThatPrimaryAction(
            label:
                selectedText == null
                    ? 'Choose your side'
                    : 'Lock in $selectedText',
            onPressed: selectedText == null ? null : _submitAnswer,
            loading: _isSubmitting,
            icon: Icons.lock_rounded,
          ),
          const SizedBox(height: 10),
          Text(
            'Your pick stays private until both of you answer.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.mutedInk,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ThisOrThatStageLabel(
                text: widget.tone,
                icon: _toneIcon(widget.tone),
                color: palette.thisColor,
              ),
              const Spacer(),
              ThisOrThatPartnerPresence(
                partnerName: widget.partnerName,
                answered: _partnerAnswered,
              ),
            ],
          ),
          const SizedBox(height: 26),
          FadeTransition(
            opacity: CurvedAnimation(
              parent: _entranceController,
              curve: const Interval(0, 0.55, curve: Curves.easeOut),
            ),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _entranceController,
                  curve: const Interval(0, 0.65, curve: Curves.easeOutCubic),
                ),
              ),
              child: Text(
                widget.questionText,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  letterSpacing: 0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No wrong answer. Pick the one that feels true first.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: AnimatedBuilder(
              animation: _entranceController,
              builder: (context, child) {
                final value =
                    CurvedAnimation(
                      parent: _entranceController,
                      curve: const Interval(
                        0.18,
                        1,
                        curve: Curves.easeOutCubic,
                      ),
                    ).value;
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 26 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 210),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ThisOrThatChoiceCard(
                        side: 'a',
                        text: widget.optionA,
                        emoji: widget.emojiA,
                        selected: _selectedChoice == 'a',
                        onTap: () => _selectChoice('a'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ThisOrThatChoiceCard(
                        side: 'b',
                        text: widget.optionB,
                        emoji: widget.emojiB,
                        selected: _selectedChoice == 'b',
                        onTap: () => _selectChoice('b'),
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

  IconData _toneIcon(String tone) {
    switch (tone.toLowerCase()) {
      case 'romantic':
        return Icons.favorite_rounded;
      case 'playful':
        return Icons.celebration_rounded;
      case 'spicy':
        return Icons.local_fire_department_rounded;
      case 'intimate':
        return Icons.nights_stay_rounded;
      default:
        return Icons.people_alt_rounded;
    }
  }
}
