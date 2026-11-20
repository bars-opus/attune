import 'dart:math' as math;
import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/platform/feel/game_burst.dart';
import 'package:attune/features/games/platform/feel/game_feedback.dart';
import 'package:attune/features/games/platform/feel/game_motion.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/platform/shell/game_buttons.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/match_indicator.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RevealScreen extends ConsumerStatefulWidget {
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
    this.nextLabel,
    this.celebrate = true,
  });

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
  final FutureOr<void> Function() onNext;
  final VoidCallback? onPrevious;
  final bool hasPrevious;
  final String? nextLabel;
  final bool celebrate;

  @override
  ConsumerState<RevealScreen> createState() => _RevealScreenState();
}

class _RevealScreenState extends ConsumerState<RevealScreen>
    with SingleTickerProviderStateMixin {
  /// Your pick turns over, then theirs a beat later, then the verdict.
  static final Duration _total =
      GameMotion.stagger + GameMotion.enter + GameMotion.settle;

  late final AnimationController _controller = AnimationController(
    duration: _total,
    vsync: this,
  );

  /// Where [at] falls in the whole run, from 0 to 1.
  static double _share(Duration at) =>
      at.inMicroseconds / _total.inMicroseconds;

  /// The [index]th pick's turn: it starts a stagger after the one before.
  static Interval _turn(int index) => Interval(
    _share(GameMotion.stagger * index),
    _share(GameMotion.stagger * index + GameMotion.enter),
  );

  /// When the second pick is down: the reveal has landed.
  static final double _landing = _share(GameMotion.stagger + GameMotion.enter);

  late final Animation<double> _resultAnimation = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _share(GameMotion.stagger + GameMotion.enter * 0.75),
      1,
      curve: Curves.easeOutBack,
    ),
  );

  bool _started = false;
  bool _landed = false;
  int _bursts = 0;
  bool _isAdvancing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.duration = GameMotion.of(context, _total);
    if (reduceMotionOf(context)) {
      // Both picks are down on the first frame, and nothing ticks.
      _controller.value = 1;
      _land();
    } else {
      _controller.addListener(_watchForLanding);
      _controller.forward();
    }
  }

  void _watchForLanding() {
    if (_landed || _controller.value < _landing) return;
    _controller.removeListener(_watchForLanding);
    setState(_land);
  }

  /// The moment both picks are showing. Once per screen, however often it
  /// rebuilds; a round looked back on ([RevealScreen.celebrate] false)
  /// replays nothing.
  void _land() {
    if (_landed) return;
    _landed = true;
    if (!widget.celebrate) return;
    if (widget.isMatch) {
      _bursts = 1;
      ref.read(gameFeedbackProvider).fire(GameEvent.match);
    } else {
      ref.read(gameFeedbackProvider).fire(GameEvent.reveal);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _advance() async {
    if (_isAdvancing) return;
    setState(() => _isAdvancing = true);
    try {
      await Future<void>.sync(widget.onNext);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The next round is not ready yet. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = widget.roundNumber == widget.totalRounds;
    return ThisOrThatGameScaffold(
      roundNumber: widget.roundNumber,
      totalRounds: widget.totalRounds,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GamePrimaryButton(
            label:
                widget.nextLabel ?? (isLast ? 'See our result' : 'Next round'),
            icon:
                isLast
                    ? Icons.emoji_events_rounded
                    : Icons.arrow_forward_rounded,
            onTap: _advance,
            busy: _isAdvancing,
          ),
          if (widget.hasPrevious) ...[
            const SizedBox(height: 10),
            GameSecondaryButton(
              label: 'Previous round',
              onTap: widget.onPrevious,
            ),
          ],
        ],
      ),
      child: ThisOrThatCentredBody(builder: _body),
    );
  }

  /// The question's height in [style], [width] wide, as it will be drawn.
  double _questionHeight(TextStyle? style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: widget.questionText, style: style),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// The question, the two picks and the verdict, fitted to [room].
  ///
  /// The verdict is the point of the screen, so it must be in view without
  /// scrolling. The picks give way to make that so: they stand tall
  /// (up to 168 inside) where there is room, shrink toward 96 where there
  /// is less, and on the shortest phones the whole screen tightens -- a
  /// smaller question, smaller picks, closer gaps. Only content that cannot
  /// fit even then, such as two long options, scrolls.
  Widget _body(BuildContext context, BoxConstraints room) {
    final palette = ThisOrThatPalette.of(context);
    final headline = Theme.of(context).textTheme.headlineSmall?.copyWith(
      color: palette.ink,
      fontWeight: FontWeight.w800,
      height: 1.15,
      letterSpacing: 0,
    );

    // Everything but the question and the picks' own height: the label,
    // the captions, the tiles' padding and shadow, the verdict and the
    // gaps between, with a little to spare.
    const roomyRest = 226.0 + 20;
    const compactRest = 184.0 + 16;
    final spare =
        room.maxHeight - roomyRest - _questionHeight(headline, room.maxWidth);
    final compact = spare < 96;
    final question =
        compact ? headline?.copyWith(fontSize: 20, height: 1.15) : headline;
    final pickHeight =
        compact
            ? (room.maxHeight -
                    compactRest -
                    _questionHeight(question, room.maxWidth))
                .clamp(0.0, 96.0)
            : spare.clamp(96.0, 168.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        ThisOrThatStageLabel(
          text: 'The reveal',
          icon: Icons.visibility_rounded,
          // On the game's orange, where only white reads.
          color: palette.ink,
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          widget.questionText,
          textAlign: TextAlign.center,
          style: question,
        ),
        SizedBox(height: compact ? 14 : 24),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The captions are said with their picks, below; on their
                // own they would be read as a list of names.
                ExcludeSemantics(
                  child: Row(
                    // Bottoms aligned, so a name on two lines still sits
                    // right on its tile.
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(child: _PickCaption(text: 'YOU')),
                      const SizedBox(width: _gap),
                      Expanded(
                        child: _PickCaption(text: _partner.toUpperCase()),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 8 : 10),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _TurningPick(
                          tileKey: const ValueKey('this-or-that-reveal-you'),
                          turnKey: const ValueKey(
                            'this-or-that-reveal-you-flip',
                          ),
                          animation: _controller,
                          turn: _turn(0),
                          fromLeft: true,
                          face:
                              widget.userChoice == 'b'
                                  ? palette.thatColor
                                  : palette.thisColor,
                          text: widget.userChoiceText,
                          emoji: widget.userChoiceEmoji,
                          owner: 'You',
                          minHeight: pickHeight,
                          compact: compact,
                        ),
                      ),
                      const SizedBox(width: _gap),
                      Expanded(
                        child: _TurningPick(
                          tileKey: const ValueKey(
                            'this-or-that-reveal-partner',
                          ),
                          turnKey: const ValueKey(
                            'this-or-that-reveal-partner-flip',
                          ),
                          animation: _controller,
                          turn: _turn(1),
                          fromLeft: false,
                          face:
                              widget.partnerChoice == 'b'
                                  ? palette.thatColor
                                  : palette.thisColor,
                          text: widget.partnerChoiceText,
                          emoji: widget.partnerChoiceEmoji,
                          owner:
                              _partnerKnown
                                  ? widget.partnerName
                                  : 'Your partner',
                          minHeight: pickHeight,
                          compact: compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Over the pair, from the seam between them. It plays when
            // [_bursts] goes up, which happens once, on a match.
            Positioned.fill(
              child: Center(
                child: GameBurst(
                  count: _bursts,
                  color: GameTheme.onGround,
                  size: 240,
                  rays: 12,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 12 : 22),
        MatchIndicator(isMatch: widget.isMatch, animation: _resultAnimation),
      ],
    );
  }

  /// The router's stand-in when the partner's name is not known.
  bool get _partnerKnown => widget.partnerName != 'Partner';

  /// Who the second pick belongs to, as a caption says it.
  String get _partner => _partnerKnown ? widget.partnerName : 'your partner';

  static const double _gap = 12;
}

/// "YOU" or the partner's name, over their pick. On the backdrop, so white.
class _PickCaption extends StatelessWidget {
  const _PickCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      style: const TextStyle(
        color: GameTheme.onGround,
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// One pick: a tile in its option's colour that turns over into view.
///
/// It starts edge-on and swings round to face the player, overshooting a
/// little before it settles. There is no fade: edge-on, it is already
/// invisible. At rest the transform is exactly none.
class _TurningPick extends StatelessWidget {
  const _TurningPick({
    required this.tileKey,
    required this.turnKey,
    required this.animation,
    required this.turn,
    required this.fromLeft,
    required this.face,
    required this.text,
    required this.emoji,
    required this.owner,
    required this.minHeight,
    required this.compact,
  });

  final Key tileKey;
  final Key turnKey;
  final Animation<double> animation;
  final Interval turn;
  final bool fromLeft;
  final Color face;
  final String text;
  final String emoji;

  /// Whose pick it is: "You", or the partner. Said with the pick.
  final String owner;

  /// The least height inside the tile's padding.
  final double minHeight;

  /// Smaller words and padding, for the shortest phones.
  final bool compact;

  Matrix4 _at(double progress) {
    if (progress >= 1) return Matrix4.identity();
    final eased = GameMotion.settleCurve.transform(progress);
    final angle = (1 - eased) * (math.pi / 2) * (fromLeft ? -1 : 1);
    return Matrix4.identity()
      // A little perspective, so the turn reads as a turn.
      ..setEntry(3, 2, 0.0012)
      ..translate(0.0, 18 * (1 - eased))
      ..rotateY(angle);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ThisOrThatPalette.of(context).inkOn(face);
    final tile = GameTile(
      key: tileKey,
      color: face,
      radius: 20,
      depth: 6,
      semanticLabel: '$owner: $text',
      padding:
          compact
              ? const EdgeInsets.fromLTRB(12, 12, 12, 14)
              : const EdgeInsets.fromLTRB(14, 20, 14, 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (emoji.isNotEmpty) ...[
              Text(
                emoji,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: compact ? 28 : 36,
                  height: 1,
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink,
                fontSize: compact ? 17 : 19,
                height: 1.18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      child: tile,
      builder:
          (context, tile) => Transform(
            key: turnKey,
            alignment: Alignment.center,
            transform: _at(turn.transform(animation.value)),
            child: tile,
          ),
    );
  }
}
