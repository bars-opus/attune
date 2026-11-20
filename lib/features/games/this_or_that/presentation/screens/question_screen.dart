import 'dart:async';
import 'dart:io';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_coach.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_tab_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    this.partnerAnswered = false,
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
  final bool partnerAnswered;
  final bool isCustom;
  final VoidCallback? onAnswerSubmitted;

  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedChoice;
  bool _isSubmitting = false;
  bool _queuedOffline = false;
  bool _startedEntrance = false;
  Timer? _retryTimer;

  /// What the tutorial points at: the card's tabs and the lock button.
  final GlobalKey _tabRowKey = GlobalKey();
  final GlobalKey _lockKey = GlobalKey();

  /// Raised by How to play, to show the tutorial again.
  int _coachReplay = 0;
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_restorePendingAnswer());
    // Kept mounted behind the privacy cover (stories Wave 3): a queued
    // pick waits while Attune is not on screen, then retries at once.
    ref.listenManual<bool>(appContentVisibleProvider, (prev, next) {
      if (next && prev == false) unawaited(_retryPendingAnswer());
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
    _retryTimer?.cancel();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _submitAnswer({bool automatic = false}) async {
    final selected = _selectedChoice;
    if (selected == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    if (!automatic) ref.read(gameFeedbackProvider).fire(GameEvent.place);

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    var savedLocally = false;
    try {
      await ref
          .read(thisOrThatAnswerOutboxProvider)
          .save(userId: userId, roundId: widget.roundId, choice: selected);
      savedLocally = true;
    } catch (_) {
      // The network request can still succeed even if secure storage is
      // temporarily unavailable; only claim local safety when it was written.
    }

    try {
      final request = (
        roundId: widget.roundId,
        choice: selected,
        isPartnerA: widget.isPartnerA,
      );
      ref.invalidate(submitAnswerProvider(request));
      await ref.read(submitAnswerProvider(request).future);
      await _removePendingAnswer(userId);
      if (mounted) widget.onAnswerSubmitted?.call();
    } catch (error) {
      if (!mounted) return;
      if (savedLocally && _isRetryable(error)) {
        setState(() => _queuedOffline = true);
        _startRetryTimer();
      } else {
        if (savedLocally) await _removePendingAnswer(userId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your pick was not saved. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _restorePendingAnswer() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    try {
      final pending = await ref
          .read(thisOrThatAnswerOutboxProvider)
          .read(userId: userId, roundId: widget.roundId);
      if (!mounted || pending == null) return;
      setState(() {
        _selectedChoice = pending.choice;
        _queuedOffline = true;
      });
      _startRetryTimer();
      unawaited(_retryPendingAnswer());
    } catch (_) {
      // A cache miss must never prevent the live question from rendering.
    }
  }

  void _startRetryTimer() {
    _retryTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_retryPendingAnswer()),
    );
  }

  Future<void> _retryPendingAnswer() async {
    if (!mounted || !_queuedOffline || _isSubmitting) return;
    if (!ref.read(appContentVisibleProvider)) return;
    await _submitAnswer(automatic: true);
  }

  Future<void> _removePendingAnswer(String userId) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    try {
      await ref
          .read(thisOrThatAnswerOutboxProvider)
          .remove(userId: userId, roundId: widget.roundId);
    } catch (_) {
      // The server is authoritative once submission succeeds. A stale local
      // entry is discarded on its next permanent rejection.
    }
    if (mounted) setState(() => _queuedOffline = false);
  }

  bool _isRetryable(Object error) {
    if (error is TimeoutException || error is SocketException) return true;
    if (error is PostgrestException || error is AuthException) return false;
    final message = error.toString().toLowerCase();
    return message.contains('connection') ||
        message.contains('network') ||
        message.contains('socket') ||
        message.contains('failed host lookup') ||
        message.contains('timed out');
  }

  void _selectChoice(String choice) {
    if (_isSubmitting || _selectedChoice == choice) return;
    ref.read(gameFeedbackProvider).fire(GameEvent.tap);
    setState(() => _selectedChoice = choice);
  }

  /// The partner's name, or null when the router found none and passed
  /// its placeholder: the words then say "your partner".
  String? get _partnerName {
    final name = widget.partnerName.trim();
    return thisOrThatPartnerKnown(name) ? name : null;
  }

  /// How to play, on this screen, is the tutorial again rather than the
  /// rules. The settings sheet calls this while it is still open, so it is
  /// closed first: a tutorial replayed under the sheet would not be seen.
  void _replayCoach() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).popUntil((other) => other == route);
    }
    setState(() => _coachReplay++);
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

    final partner = _partnerName;

    return ThisOrThatGameScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      onHowToPlay: _replayCoach,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThisOrThatPrimaryAction(
            key: _lockKey,
            label:
                selectedText == null
                    ? 'Choose your side'
                    : 'Lock in ${_selectedChoice == 'a' ? 'This' : 'That'}',
            onPressed: selectedText == null ? null : _submitAnswer,
            loading: _isSubmitting,
            icon: Icons.lock_rounded,
          ),
          const SizedBox(height: 10),
          Text(
            'Your pick stays hidden until ${partner ?? 'your partner'} has '
            'answered too.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.mutedInk,
              letterSpacing: 0,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child:
                _queuedOffline
                    ? Container(
                      key: const ValueKey('answer-waiting-to-connect'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: palette.thatColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: palette.thatColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 18,
                            color: palette.thatColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Waiting to connect. Your pick is saved on this device.',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: palette.ink,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
      // Around the body, not the screen: the bubble sits under the header.
      // The lock button is outside it, under the body, and is pointed at
      // all the same.
      child: GameCoach(
        gameType: 'this_or_that',
        replay: _coachReplay,
        steps: [
          GameCoachStep(
            text: 'Pull THIS or THAT forward to choose.',
            target: _tabRowKey,
          ),
          GameCoachStep(
            text:
                'Then lock it in. ${partner ?? 'Your partner'} will not see '
                'your pick until they have answered too.',
            target: _lockKey,
          ),
          // Back at the tabs: a step that pointed at nothing would put its
          // bubble at the top, over the tabs on a small phone.
          GameCoachStep(
            text:
                'When you have both picked, the two answers turn over '
                'together.',
            target: _tabRowKey,
          ),
        ],
        child: Column(
          children: [
            Row(
              children: [
                // White, like the header: this row sits on the game's
                // orange, where the coral and the muted grey do not read.
                ThisOrThatStageLabel(
                  text: widget.tone,
                  icon: _toneIcon(widget.tone),
                  color: GameTheme.onGround,
                ),
                const Spacer(),
                ThisOrThatPartnerPresence(
                  partnerName: widget.partnerName,
                  answered: widget.partnerAnswered,
                ),
              ],
            ),
            // The round is in the header; the body does not repeat it.
            const SizedBox(height: 12),
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
                // One card that BECOMES the answer, rather than two cards
                // to compare. Pulling a tab forward floods the card with
                // that option's colour, and the colour arriving is the
                // confirmation -- there is no separate submit.
                //
                // The card, with the line under it, is centred in the
                // space it has, so the tabs sit above the middle of the
                // screen. The tutorial's bubble then goes below them, over
                // empty space and the card's lower half, and the tabs stay
                // free to pull while it shows -- on a small phone too, where
                // there is no room for the bubble above them. It still
                // scrolls where a long question does not fit.
                child: LayoutBuilder(
                  builder:
                      (context, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ThisOrThatTabRowTarget(
                                  target: _tabRowKey,
                                  child: ThisOrThatTabCard(
                                    questionText: widget.questionText,
                                    optionA: widget.optionA,
                                    optionB: widget.optionB,
                                    emojiA: widget.emojiA,
                                    emojiB: widget.emojiB,
                                    active: switch (_selectedChoice) {
                                      'a' => ThisOrThatTab.thisOption,
                                      'b' => ThisOrThatTab.thatOption,
                                      _ => ThisOrThatTab.question,
                                    },
                                    // Null while submitting, so a committed
                                    // answer cannot be changed mid-flight.
                                    onSelect:
                                        _isSubmitting
                                            ? null
                                            : (tab) => _selectChoice(
                                              tab == ThisOrThatTab.thisOption
                                                  ? 'a'
                                                  : 'b',
                                            ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No wrong answer. Pick the one that feels '
                                  'true first.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color: GameTheme.onGround,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ),
          ],
        ),
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
