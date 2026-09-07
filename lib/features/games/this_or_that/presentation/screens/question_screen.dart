import 'dart:async';
import 'dart:io';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
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
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_restorePendingAnswer());
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
    if (!automatic) ref.read(hapticsProvider).medium();

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
                    : 'Lock in ${_selectedChoice == 'a' ? 'This' : 'That'}',
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
                answered: widget.partnerAnswered,
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
