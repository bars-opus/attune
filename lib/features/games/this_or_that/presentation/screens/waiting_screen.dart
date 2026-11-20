import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
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

  Timer? _handoff;

  /// How long the round stays on screen before the game hands off to the
  /// chat card.
  ///
  /// Matches the session games' grace window rather than the shorter
  /// RoundHandoff pause: partners playing in the same room answer within
  /// seconds, and bouncing them out only to tap back in would be worse
  /// than a brief wait. Past this they are not in the same room.
  static const _graceWindow = Duration(seconds: 20);

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

    // This round is answered and saved; the game is with the partner,
    // who may answer in an hour. Holding the player on a spinner until
    // then made the game feel broken -- the chat card carries the state
    // better than a screen nobody is looking at.
    _handoff = Timer(_graceWindow, _leaveToChat);
  }

  /// Leaves for the chat, unless the player is mid-edit.
  ///
  /// Changing your pick is the one thing this screen is FOR beyond
  /// waiting, and closing it under someone's fingers would discard the
  /// change they were making.
  void _leaveToChat() {
    if (!mounted || _isEditing || _isUpdatingChoice) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _reminderTimer?.cancel();
    _handoff?.cancel();
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
    final face = _currentChoice == 'b' ? palette.thatColor : palette.thisColor;
    final ink = palette.inkOn(face);
    // The router's stand-in when the name is not known: the screen then
    // says "your partner" rather than calling them "Partner".
    final named = widget.partnerName != 'Partner';
    final partner = named ? widget.partnerName : 'your partner';

    return ThisOrThatGameScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      onBack: _showExitConfirmation,
      child: ThisOrThatCentredBody(
        builder:
            (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                // The player's own pick, in its own colour: the one thing
                // on this screen that is theirs, so it leads.
                GameTile(
                  key: const ValueKey('this-or-that-locked-pick'),
                  color: face,
                  radius: 22,
                  depth: 6,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ThisOrThatStageLabel(
                          text: 'Your locked pick',
                          icon: Icons.lock_rounded,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.questionText,
                        style: TextStyle(
                          color: ink,
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AnimatedSwitcher(
                        duration: GameMotion.of(context, GameMotion.settle),
                        switchInCurve: GameMotion.settleCurve,
                        // The new pick springs in where the old one was;
                        // the old one goes at once rather than fading
                        // under it.
                        layoutBuilder:
                            (current, previous) => current ?? const SizedBox(),
                        transitionBuilder:
                            (child, animation) => ScaleTransition(
                              scale: Tween(
                                begin: 0.9,
                                end: 1.0,
                              ).animate(animation),
                              alignment: Alignment.centerLeft,
                              child: child,
                            ),
                        child: Text(
                          '${choiceEmoji ?? ''} $choiceText'.trim(),
                          key: ValueKey(_currentChoice),
                          style: TextStyle(
                            color: ink,
                            fontSize: 24,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const ThisOrThatWaitingMark(size: 96),
                const SizedBox(height: 12),
                Text(
                  named ? '$partner is choosing' : 'Your partner is choosing',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your answer is tucked away. The reveal begins as soon as '
                  '$partner locks theirs in.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.mutedInk,
                    height: 1.4,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 24),
                if (reduceMotionOf(context))
                  _buildChoiceEditor()
                else
                  AnimatedSize(
                    duration: GameMotion.of(context, GameMotion.settle),
                    curve: GameMotion.enterCurve,
                    alignment: Alignment.topCenter,
                    child: _buildChoiceEditor(),
                  ),
                if (_showRemindButton) ...[
                  const SizedBox(height: 12),
                  GameSecondaryButton(
                    // While it is on its way the button says so, and takes no
                    // second tap.
                    label: _isSendingReminder ? 'Sending…' : 'Nudge $partner',
                    onTap: _isSendingReminder ? null : _sendReminder,
                  ),
                ],
              ],
            ),
      ),
    );
  }

  Widget _buildChoiceEditor() {
    if (!_isEditing) {
      return GameSecondaryButton(
        key: const ValueKey('change-pick'),
        label: 'Change my pick',
        onTap:
            _isUpdatingChoice ? null : () => setState(() => _isEditing = true),
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
          (context) => thisOrThatDarkTheme(
            context,
            child: AlertDialog(
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
          ),
    );
    if (exit == true && mounted) Navigator.of(context).maybePop();
  }
}
