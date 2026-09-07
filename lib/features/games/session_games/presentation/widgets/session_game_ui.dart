import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// The shared look for Scenario, Mirror, Sliding Scale and Love Map.
///
/// These four share a flow -- answer, wait, reveal, end -- and differed
/// only in how an answer is captured. They should share a look for the
/// same reason: a player moving between them is in one place, not four.
///
/// Each game still gets its own accent, because the games ask genuinely
/// different things and the colour is the fastest way to say which one
/// you are in.
class SessionGamePalette {
  const SessionGamePalette({
    required this.accent,
    required this.accentSoft,
    required this.canvas,
    required this.panel,
    required this.ink,
    required this.mutedInk,
    required this.line,
    required this.yours,
    required this.theirs,
  });

  final Color accent;
  final Color accentSoft;
  final Color canvas;
  final Color panel;
  final Color ink;
  final Color mutedInk;
  final Color line;

  /// The two voices on the reveal screen. Warm for you, cool for them --
  /// the same pairing This or That uses, so a player already knows how to
  /// read it.
  final Color yours;
  final Color theirs;

  static SessionGamePalette of(BuildContext context, {String? gameType}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentFor(gameType, dark: dark);

    return dark
        ? SessionGamePalette(
          accent: accent,
          accentSoft: accent.withValues(alpha: 0.16),
          canvas: const Color(0xFF101214),
          panel: const Color(0xFF1A1D21),
          ink: const Color(0xFFF7F6F3),
          mutedInk: const Color(0xFFA6A9AF),
          line: const Color(0xFF31343A),
          yours: const Color(0xFFFF9E7A),
          theirs: const Color(0xFF7FB6FF),
        )
        : SessionGamePalette(
          accent: accent,
          accentSoft: accent.withValues(alpha: 0.10),
          canvas: const Color(0xFFF8F6F2),
          panel: const Color(0xFFFFFFFF),
          ink: const Color(0xFF1F2126),
          mutedInk: const Color(0xFF6C6E76),
          line: const Color(0xFFE4E1DB),
          yours: const Color(0xFFC9552A),
          theirs: const Color(0xFF2F63C4),
        );
  }

  /// One accent per game. Scenario is amber because it poses situations
  /// with no right answer; Mirror is teal because it is about reflection;
  /// Sliding Scale is indigo, Love Map rose.
  static Color _accentFor(String? gameType, {required bool dark}) {
    switch (gameType) {
      case 'mirror':
        return dark ? const Color(0xFF5FD4C4) : const Color(0xFF16897A);
      case 'sliding_scale':
        return dark ? const Color(0xFF8FA6FF) : const Color(0xFF4257C4);
      case 'love_map':
        return dark ? const Color(0xFFFF9BB5) : const Color(0xFFC94670);
      case 'scenario':
      default:
        return dark ? const Color(0xFFF5C063) : const Color(0xFFB07A16);
    }
  }
}

/// Carries the game type down the tree.
///
/// Without it every widget would take a `gameType` it does not use purely
/// to forward it, and one that forgot would render another game's accent.
class SessionGameTypeScope extends InheritedWidget {
  const SessionGameTypeScope({
    super.key,
    required this.gameType,
    required super.child,
  });

  final String? gameType;

  static String? of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SessionGameTypeScope>()
          ?.gameType;

  @override
  bool updateShouldNotify(SessionGameTypeScope old) => old.gameType != gameType;
}

/// A small capitalised marker.
class SessionGameStageLabel extends StatelessWidget {
  const SessionGameStageLabel({
    super.key,
    required this.text,
    this.icon,
    this.color,
  });

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final tint = color ?? palette.mutedInk;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tint,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

/// The question, on its own card.
///
/// Arrives rather than being already there, so a new question reads as
/// something handed to you.
class SessionGameQuestionCard extends StatefulWidget {
  const SessionGameQuestionCard({
    super.key,
    required this.text,
    this.label,
    this.compact = false,
  });

  final String text;
  final String? label;
  final bool compact;

  @override
  State<SessionGameQuestionCard> createState() =>
      _SessionGameQuestionCardState();
}

class _SessionGameQuestionCardState extends State<SessionGameQuestionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        ),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(widget.compact ? 18 : 24),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(widget.compact ? 20 : 26),
            border: Border.all(color: palette.line),
            boxShadow: [
              BoxShadow(
                color: palette.accent.withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.label != null) ...[
                SessionGameStageLabel(
                  text: widget.label!,
                  color: palette.accent,
                ),
                SizedBox(height: widget.compact ? 10 : 14),
              ],
              Text(
                widget.text,
                style: (widget.compact
                        ? textTheme.titleMedium
                        : textTheme.headlineSmall)
                    ?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.34,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One answer option.
///
/// Deliberately identical in weight to its siblings: these games pose
/// situations with no right answer, and styling one as preferred would
/// turn a conversation starter into a test you can fail.
class SessionGameOptionCard extends StatelessWidget {
  const SessionGameOptionCard({
    super.key,
    required this.text,
    required this.onTap,
    this.selected = false,
    this.index,
  });

  final String text;
  final VoidCallback? onTap;
  final bool selected;

  /// Position in the list, shown as a quiet marker so options can be
  /// referred to out loud ("I went with the second one").
  final int? index;

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = reduceMotionOf(context);

    return Semantics(
      button: onTap != null,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? palette.accentSoft : palette.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? palette.accent : palette.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (index != null) ...[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? palette.accent
                            : palette.line.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index! + 1}',
                    style: textTheme.labelSmall?.copyWith(
                      color: selected ? palette.canvas : palette.mutedInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  text,
                  style: textTheme.bodyLarge?.copyWith(
                    color: palette.ink,
                    height: 1.32,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One voice on the reveal screen.
///
/// The two answers get distinct colour and a name, because "You said" and
/// "They said" in identical grey is a transcript, not a moment.
class SessionGameAnswerCard extends StatelessWidget {
  const SessionGameAnswerCard({
    super.key,
    required this.speaker,
    required this.answer,
    required this.isYours,
    this.matched = false,
  });

  final String speaker;
  final String answer;
  final bool isYours;

  /// Both said the same thing. Worth marking -- it is the outcome these
  /// games are quietly hoping for.
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final tint = isYours ? palette.yours : palette.theirs;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: matched ? tint : palette.line,
          width: matched ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              SessionGameStageLabel(text: speaker, color: tint),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            answer.isEmpty ? 'No answer recorded.' : answer,
            style: textTheme.titleMedium?.copyWith(
              color: answer.isEmpty ? palette.mutedInk : palette.ink,
              fontWeight: FontWeight.w600,
              height: 1.35,
              fontStyle: answer.isEmpty ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary action.
class SessionGamePrimaryAction extends StatelessWidget {
  const SessionGamePrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final enabled = onPressed != null && !busy;

    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          disabledBackgroundColor: palette.accent.withValues(alpha: 0.35),
          foregroundColor: palette.canvas,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        child:
            busy
                ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20),
                      const SizedBox(width: 10),
                    ],
                    Text(label),
                  ],
                ),
      ),
    );
  }
}

/// A slow breathing mark for waiting on a partner.
///
/// Not a spinner. A spinner says "something is loading and may be stuck";
/// this wait is on a person who may answer in an hour, and the difference
/// matters -- one invites anxiety, the other patience.
class SessionGameWaitingMark extends StatefulWidget {
  const SessionGameWaitingMark({super.key, this.color});

  final Color? color;

  @override
  State<SessionGameWaitingMark> createState() => _SessionGameWaitingMarkState();
}

class _SessionGameWaitingMarkState extends State<SessionGameWaitingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SessionGamePalette.of(
      context,
      gameType: SessionGameTypeScope.of(context),
    );
    final tint = widget.color ?? palette.accent;

    if (reduceMotionOf(context)) {
      return Icon(Icons.more_horiz_rounded, color: tint, size: 30);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, _) => CustomPaint(
            size: const Size(64, 64),
            painter: _BreathPainter(_controller.value, tint),
          ),
    );
  }
}

/// Two rings breathing out of a still centre.
///
/// Slow on purpose: the tempo is closer to breathing than to loading.
class _BreathPainter extends CustomPainter {
  const _BreathPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var ring = 0; ring < 2; ring++) {
      // Offset so the two rings never pulse together, which would read
      // as one thick ring rather than something breathing.
      final phase = (progress + (ring * 0.5)) % 1;
      canvas.drawCircle(
        centre,
        maxRadius * (0.25 + phase * 0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color.withValues(alpha: (1 - phase) * 0.5),
      );
    }

    canvas.drawCircle(centre, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BreathPainter old) =>
      old.progress != progress || old.color != color;
}
