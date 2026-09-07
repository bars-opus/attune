import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WaitingScreen extends ConsumerStatefulWidget {
  const WaitingScreen({
    super.key,
    required this.sessionId,
    required this.roundId,
    required this.questionText,
    required this.userChoice,
    required this.userChoiceText,
    required this.userChoiceEmoji,
    required this.optionA,
    required this.optionB,
    this.emojiA,
    this.emojiB,
    required this.roundNumber,
    required this.totalRounds,
    required this.isPartnerA,
    this.partnerName = 'Partner',
    this.answeredAt,
    this.onRoundUpdated,
  });

  final String sessionId;
  final String roundId;
  final String questionText;
  final String userChoice;
  final String userChoiceText;
  final String userChoiceEmoji;
  final String optionA;
  final String optionB;
  final String? emojiA;
  final String? emojiB;
  final int roundNumber;
  final int totalRounds;
  final bool isPartnerA;
  final String partnerName;
  final DateTime? answeredAt;
  final VoidCallback? onRoundUpdated;

  @override
  ConsumerState<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends ConsumerState<WaitingScreen> {
  Timer? _reminderTimer;
  bool _showRemindButton = false;
  bool _isSendingReminder = false;
  bool _isEditing = false;
  bool _isUpdatingChoice = false;
  late String _currentChoice;

  @override
  void initState() {
    super.initState();
    _currentChoice = widget.userChoice;
    final elapsed = DateTime.now().difference(
      widget.answeredAt ?? DateTime.now(),
    );
    final reminderDelay = const Duration(hours: 2) - elapsed;
    if (reminderDelay <= Duration.zero) {
      _showRemindButton = true;
    } else {
      _scheduleReminder(reminderDelay);
    }
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    super.dispose();
  }

  void _enableRemindButton() {
    if (mounted) setState(() => _showRemindButton = true);
  }

  void _scheduleReminder(Duration delay) {
    _reminderTimer?.cancel();
    _reminderTimer = Timer(delay, _enableRemindButton);
  }

  Future<void> _changeChoice(String choice) async {
    if (_isUpdatingChoice || choice == _currentChoice) {
      if (choice == _currentChoice) setState(() => _isEditing = false);
      return;
    }

    final previous = _currentChoice;
    setState(() {
      _currentChoice = choice;
      _isUpdatingChoice = true;
      _isEditing = false;
    });
    ref.read(hapticsProvider).selection();
    ref.read(soundServiceProvider).play(AppSound.gameTap);

    try {
      final request = (
        roundId: widget.roundId,
        choice: choice,
        isPartnerA: widget.isPartnerA,
      );
      ref.invalidate(submitAnswerProvider(request));
      await ref.read(submitAnswerProvider(request).future);
      widget.onRoundUpdated?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _currentChoice = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your new pick was not saved.')),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingChoice = false);
    }
  }

  Future<void> _sendReminder() async {
    if (_isSendingReminder) return;
    setState(() => _isSendingReminder = true);

    try {
      ref.invalidate(sendReminderProvider(widget.sessionId));
      await ref.read(sendReminderProvider(widget.sessionId).future);
      if (!mounted) return;
      ref.read(hapticsProvider).light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('A gentle nudge was sent to ${widget.partnerName}.'),
        ),
      );
      setState(() => _showRemindButton = false);
      _scheduleReminder(const Duration(hours: 4));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The reminder could not be sent yet.')),
      );
    } finally {
      if (mounted) setState(() => _isSendingReminder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final choiceText = _currentChoice == 'a' ? widget.optionA : widget.optionB;
    final choiceEmoji = _currentChoice == 'a' ? widget.emojiA : widget.emojiB;

    return ThisOrThatGameScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Leave game',
        onPressed: _showExitConfirmation,
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const ThisOrThatWaitingMark(),
          const SizedBox(height: 12),
          Text(
            '${widget.partnerName} is choosing',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your answer is tucked away. The reveal begins as soon as they lock theirs in.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.panel.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              children: [
                ThisOrThatStageLabel(
                  text: 'Your locked pick',
                  icon: Icons.lock_rounded,
                  color: palette.mutedInk,
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration:
                      reduceMotionOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                  child: Text(
                    '${choiceEmoji ?? ''} $choiceText'.trim(),
                    key: ValueKey(_currentChoice),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.questionText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.mutedInk,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (reduceMotionOf(context))
            _buildChoiceEditor()
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _buildChoiceEditor(),
            ),
          if (_showRemindButton) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _isSendingReminder ? null : _sendReminder,
              icon:
                  _isSendingReminder
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.notifications_active_outlined),
              label: Text('Nudge ${widget.partnerName}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChoiceEditor() {
    if (!_isEditing) {
      return TextButton.icon(
        key: const ValueKey('change-pick'),
        onPressed:
            _isUpdatingChoice ? null : () => setState(() => _isEditing = true),
        icon: const Icon(Icons.swap_horiz_rounded),
        label: const Text('Change my pick'),
      );
    }

    return SizedBox(
      key: const ValueKey('choice-editor'),
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ThisOrThatChoiceCard(
              side: 'a',
              text: widget.optionA,
              emoji: widget.emojiA,
              compact: true,
              selected: _currentChoice == 'a',
              onTap: () => _changeChoice('a'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ThisOrThatChoiceCard(
              side: 'b',
              text: widget.optionB,
              emoji: widget.emojiB,
              compact: true,
              selected: _currentChoice == 'b',
              onTap: () => _changeChoice('b'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showExitConfirmation() async {
    final exit = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave for now?'),
            content: const Text(
              'Your pick is saved. You can come back when your partner answers.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep waiting'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave game'),
              ),
            ],
          ),
    );
    if (exit == true && mounted) Navigator.of(context).maybePop();
  }
}
