import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// Truth or Dare's own palette.
///
/// The game has one irreducible idea -- a card with two faces -- so the
/// palette is built around a pair: truth is cool and considered, dare is
/// warm and forward. Every screen borrows one of the two, which is what
/// lets a player know which half of the game they are in before reading
/// a word.
///
/// Tone tints the whole board on top of that. A Spicy session should not
/// look like a Playful one, and the difference has to be visible without
/// naming it, because naming it every screen would be nagging.
/// Carries the session's tone down the tree.
///
/// Without this every widget would need a `tone` parameter it does not
/// use, purely to forward it to the one that does -- and any widget that
/// forgot would silently render a Playful glow inside a Spicy session,
/// which is exactly what happened before this existed.
class TruthOrDareToneScope extends InheritedWidget {
  const TruthOrDareToneScope({
    super.key,
    required this.tone,
    required super.child,
  });

  final String? tone;

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TruthOrDareToneScope>()?.tone;

  @override
  bool updateShouldNotify(TruthOrDareToneScope old) => old.tone != tone;
}

class TruthOrDarePalette {
  const TruthOrDarePalette({
    required this.truth,
    required this.dare,
    required this.truthSurface,
    required this.dareSurface,
    required this.canvas,
    required this.panel,
    required this.ink,
    required this.mutedInk,
    required this.line,
    required this.toneAccent,
  });

  final Color truth;
  final Color dare;
  final Color truthSurface;
  final Color dareSurface;
  final Color canvas;
  final Color panel;
  final Color ink;
  final Color mutedInk;
  final Color line;

  /// The session's tone, carried through the board's ambient glow.
  final Color toneAccent;

  static TruthOrDarePalette of(BuildContext context, {String? tone}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Falls back to the scope, so a widget deep in the tree gets the
    // session's tone without being handed it.
    final accent = _toneAccent(
      tone ?? TruthOrDareToneScope.of(context),
      dark: dark,
    );

    return dark
        ? TruthOrDarePalette(
          truth: const Color(0xFF6FD3E8),
          dare: const Color(0xFFFF9E6B),
          truthSurface: const Color(0xFF16303A),
          dareSurface: const Color(0xFF3A2618),
          canvas: const Color(0xFF0F1113),
          panel: const Color(0xFF1A1D21),
          ink: const Color(0xFFF7F6F3),
          mutedInk: const Color(0xFFA6A9AF),
          line: const Color(0xFF31343A),
          toneAccent: accent,
        )
        : TruthOrDarePalette(
          truth: const Color(0xFF1F7C93),
          dare: const Color(0xFFD1622C),
          truthSurface: const Color(0xFFDDF2F7),
          dareSurface: const Color(0xFFFFEBE0),
          canvas: const Color(0xFFF8F6F2),
          panel: const Color(0xFFFFFFFF),
          ink: const Color(0xFF1F2126),
          mutedInk: const Color(0xFF6C6E76),
          line: const Color(0xFFE4E1DB),
          toneAccent: accent,
        );
  }

  /// Tone reads as temperature, not decoration. A player who chose Spicy
  /// should feel it on the board without being told.
  ///
  /// All five server-side tones are covered. An unhandled tone would fall
  /// to the playful green, which would quietly tell an Intimate session
  /// it was something lighter.
  static Color _toneAccent(String? tone, {required bool dark}) {
    switch (tone) {
      case 'connecting':
        return dark ? const Color(0xFF7FB2FF) : const Color(0xFF2F6BD0);
      case 'romantic':
        return dark ? const Color(0xFFFF9BB5) : const Color(0xFFCE4A70);
      case 'intimate':
        return dark ? const Color(0xFF9E7BFF) : const Color(0xFF6C4BD6);
      case 'spicy':
        return dark ? const Color(0xFFFF7A5C) : const Color(0xFFD24A26);
      case 'playful':
      default:
        return dark ? const Color(0xFF7BD88F) : const Color(0xFF2E9E58);
    }
  }

  Color accentFor(String kind) => kind == 'dare' ? dare : truth;
  Color surfaceFor(String kind) => kind == 'dare' ? dareSurface : truthSurface;
}

/// The frame every Truth or Dare screen sits in.
///
/// One scaffold rather than seven hand-built ones, so the round counter,
/// the tone glow and the safe-area handling cannot drift apart between
/// screens -- which is exactly what had happened.
class TruthOrDareScaffold extends StatelessWidget {
  const TruthOrDareScaffold({
    super.key,
    required this.child,
    this.title = 'Truth or Dare',
    this.roundNumber,
    this.totalRounds,
    this.tone,
    this.leading,
    this.actions,
    this.bottom,
    this.scrollable = false,
  });

  final Widget child;
  final String title;
  final int? roundNumber;
  final int? totalRounds;
  final String? tone;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = TruthOrDarePalette.of(context, tone: tone);
    final hasProgress = roundNumber != null && totalRounds != null;

    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: child,
      ),
    );

    return TruthOrDareToneScope(
      tone: tone,
      child: Scaffold(
        backgroundColor: palette.canvas,
        appBar: AppBar(
          backgroundColor: palette.canvas,
          surfaceTintColor: Colors.transparent,
          foregroundColor: palette.ink,
          elevation: 0,
          leading: leading,
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (hasProgress)
                Text(
                  'ROUND $roundNumber OF $totalRounds',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.mutedInk,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
          actions: actions,
          bottom:
              hasProgress
                  ? PreferredSize(
                    preferredSize: const Size.fromHeight(5),
                    child: _TurnProgressTrack(
                      value:
                          totalRounds == 0
                              ? 0
                              : roundNumber!.clamp(0, totalRounds!) /
                                  totalRounds!,
                      color: palette.toneAccent,
                      line: palette.line,
                    ),
                  )
                  : null,
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(painter: _ToneGlowPainter(palette)),
                ),
              ),
            ),
            if (scrollable)
              SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  child: Center(child: body),
                ),
              )
            else
              SafeArea(top: false, child: Center(child: body)),
          ],
        ),
        bottomNavigationBar:
            bottom == null
                ? null
                : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 580),
                        child: bottom,
                      ),
                    ),
                  ),
                ),
      ),
    );
  }
}

class _TurnProgressTrack extends StatelessWidget {
  const _TurnProgressTrack({
    required this.value,
    required this.color,
    required this.line,
  });

  final double value;
  final Color color;
  final Color line;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 5,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: line)),
          FractionallySizedBox(
            widthFactor: value.clamp(0, 1),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration:
                  reduceMotionOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder:
                  (context, t, _) =>
                      Opacity(opacity: t, child: ColoredBox(color: color)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft glow in the session's tone, low in the frame.
///
/// Ambient rather than decorative: it is the only place the chosen tone
/// is visible once the selector is behind you, and a Spicy board that
/// looked identical to a Playful one would make the choice feel like it
/// did not matter.
class _ToneGlowPainter extends CustomPainter {
  const _ToneGlowPainter(this.palette);

  final TruthOrDarePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 0.82);
    final radius = size.width * 0.9;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.toneAccent.withValues(alpha: 0.22),
            palette.toneAccent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_ToneGlowPainter old) =>
      old.palette.toneAccent != palette.toneAccent;
}

/// A small capitalised marker: "YOUR TURN", "TRUTH", "DARE".
class TruthOrDareStageLabel extends StatelessWidget {
  const TruthOrDareStageLabel({
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
    final palette = TruthOrDarePalette.of(context);
    final tint = color ?? palette.mutedInk;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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

/// The prompt itself, on the card face it belongs to.
///
/// It ARRIVES rather than simply being present: a short rise and fade as
/// the screen opens. Animating it here rather than per-screen means every
/// surface that shows a prompt gets the same beat, and none of them can
/// forget it.
class TruthOrDarePromptCard extends StatefulWidget {
  const TruthOrDarePromptCard({
    super.key,
    required this.kind,
    required this.prompt,
    this.author,
    this.compact = false,
  });

  /// 'truth' or 'dare'.
  final String kind;
  final String prompt;
  final String? author;
  final bool compact;

  @override
  State<TruthOrDarePromptCard> createState() => _TruthOrDarePromptCardState();
}

class _TruthOrDarePromptCardState extends State<TruthOrDarePromptCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
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
    final palette = TruthOrDarePalette.of(context);
    final accent = palette.accentFor(widget.kind);
    final textTheme = Theme.of(context).textTheme;
    final compact = widget.compact;

    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 26),
      decoration: BoxDecoration(
        color: palette.surfaceFor(widget.kind),
        borderRadius: BorderRadius.circular(compact ? 20 : 28),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TruthOrDareStageLabel(
            text: widget.kind,
            icon:
                widget.kind == 'dare'
                    ? Icons.local_fire_department_rounded
                    : Icons.psychology_alt_rounded,
            color: accent,
          ),
          SizedBox(height: compact ? 10 : 16),
          Text(
            widget.prompt,
            style: (compact ? textTheme.titleMedium : textTheme.headlineSmall)
                ?.copyWith(
                  color: palette.ink,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                ),
          ),
          if (widget.author != null) ...[
            const SizedBox(height: 14),
            Text(
              'Written by ${widget.author}',
              style: textTheme.bodySmall?.copyWith(
                color: palette.mutedInk,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );

    return FadeTransition(
      opacity: _controller,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        ),
        child: card,
      ),
    );
  }
}

/// The game's primary action.
class TruthOrDarePrimaryAction extends StatelessWidget {
  const TruthOrDarePrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = 'truth',
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String kind;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = TruthOrDarePalette.of(context);
    final accent = palette.accentFor(kind);
    final enabled = onPressed != null && !busy;

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          disabledBackgroundColor: accent.withValues(alpha: 0.35),
          foregroundColor: Colors.white,
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
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

/// A slow breathing mark for the waiting states.
///
/// Three dots that pulse in sequence. Deliberately unhurried: the player
/// is waiting on a person, not a server, and a fast spinner would imply
/// something is loading and stuck.
class TruthOrDareWaitingMark extends StatefulWidget {
  const TruthOrDareWaitingMark({super.key, this.color});

  final Color? color;

  @override
  State<TruthOrDareWaitingMark> createState() => _TruthOrDareWaitingMarkState();
}

class _TruthOrDareWaitingMarkState extends State<TruthOrDareWaitingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  // didChangeDependencies, not initState: reduceMotionOf reads MediaQuery,
  // and an inherited widget cannot be read before initState completes.
  // Reading it here also means the mark stops if the setting changes
  // mid-session rather than staying stuck however it started.
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
    final palette = TruthOrDarePalette.of(context);
    final tint = widget.color ?? palette.toneAccent;

    if (reduceMotionOf(context)) {
      return Icon(Icons.more_horiz_rounded, color: tint, size: 28);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder:
          (context, _) => CustomPaint(
            size: const Size(56, 14),
            painter: _WaitingDotsPainter(_controller.value, tint),
          ),
    );
  }
}

class _WaitingDotsPainter extends CustomPainter {
  const _WaitingDotsPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 3;
    final gap = size.width / (count + 1);
    for (var i = 0; i < count; i++) {
      // Offset per dot so they breathe in sequence rather than together.
      final phase = (progress + (i / count)) % 1;
      final swell = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
      canvas.drawCircle(
        Offset(gap * (i + 1), size.height / 2),
        3 + swell * 2.4,
        Paint()..color = color.withValues(alpha: 0.35 + swell * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_WaitingDotsPainter old) =>
      old.progress != progress || old.color != color;
}
