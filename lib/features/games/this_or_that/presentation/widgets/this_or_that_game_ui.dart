import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

@immutable
class ThisOrThatPalette {
  const ThisOrThatPalette({
    required this.thisColor,
    required this.thatColor,
    required this.thisSurface,
    required this.thatSurface,
    required this.canvas,
    required this.panel,
    required this.ink,
    required this.mutedInk,
    required this.line,
  });

  final Color thisColor;
  final Color thatColor;
  final Color thisSurface;
  final Color thatSurface;
  final Color canvas;
  final Color panel;
  final Color ink;
  final Color mutedInk;
  final Color line;

  static ThisOrThatPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const ThisOrThatPalette(
          thisColor: Color(0xFFFF8A76),
          thatColor: Color(0xFF8DA7FF),
          thisSurface: Color(0xFF3A2424),
          thatSurface: Color(0xFF202B46),
          canvas: Color(0xFF111214),
          panel: Color(0xFF1B1D20),
          ink: Color(0xFFF8F7F4),
          mutedInk: Color(0xFFA9ABB1),
          line: Color(0xFF34363B),
        )
        : const ThisOrThatPalette(
          thisColor: Color(0xFFD94C3D),
          thatColor: Color(0xFF3F66D4),
          thisSurface: Color(0xFFFFE5DF),
          thatSurface: Color(0xFFE4EAFF),
          canvas: Color(0xFFF7F5F1),
          panel: Color(0xFFFFFFFF),
          ink: Color(0xFF202126),
          mutedInk: Color(0xFF6D6F77),
          line: Color(0xFFE3E0DA),
        );
  }
}

class ThisOrThatGameScaffold extends StatelessWidget {
  const ThisOrThatGameScaffold({
    super.key,
    required this.child,
    this.title = 'This or That',
    this.roundNumber,
    this.totalRounds,
    this.leading,
    this.actions,
    this.bottom,
    this.scrollable = false,
  });

  final Widget child;
  final String title;
  final int? roundNumber;
  final int? totalRounds;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final hasProgress = roundNumber != null && totalRounds != null;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: child,
      ),
    );

    return Scaffold(
      backgroundColor: palette.canvas,
      appBar: AppBar(
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: leading,
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
        centerTitle: true,
        actions: actions,
        bottom:
            hasProgress
                ? PreferredSize(
                  preferredSize: const Size.fromHeight(5),
                  child: _GameProgressTrack(
                    value:
                        totalRounds == 0
                            ? 0
                            : roundNumber!.clamp(0, totalRounds!) /
                                totalRounds!,
                  ),
                )
                : null,
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(child: _SplitCanvasTexture()),
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
    );
  }
}

class _GameProgressTrack extends StatelessWidget {
  const _GameProgressTrack({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration:
          reduceMotionOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder:
          (context, progress, _) => LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: palette.line,
            valueColor: AlwaysStoppedAnimation<Color>(palette.thisColor),
          ),
    );
  }
}

class _SplitCanvasTexture extends StatelessWidget {
  const _SplitCanvasTexture();

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return CustomPaint(painter: _SplitCanvasPainter(palette));
  }
}

class _SplitCanvasPainter extends CustomPainter {
  const _SplitCanvasPainter(this.palette);

  final ThisOrThatPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final left = Paint()..color = palette.thisSurface.withValues(alpha: 0.22);
    final right = Paint()..color = palette.thatSurface.withValues(alpha: 0.22);
    final divider =
        Paint()
          ..color = palette.line.withValues(alpha: 0.45)
          ..strokeWidth = 1;

    final split =
        Path()
          ..moveTo(0, size.height * 0.08)
          ..lineTo(size.width * 0.48, 0)
          ..lineTo(size.width * 0.55, size.height)
          ..lineTo(0, size.height)
          ..close();
    canvas.drawPath(split, left);

    final other =
        Path()
          ..moveTo(size.width * 0.48, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height)
          ..lineTo(size.width * 0.55, size.height)
          ..close();
    canvas.drawPath(other, right);
    canvas.drawLine(
      Offset(size.width * 0.48, 0),
      Offset(size.width * 0.55, size.height),
      divider,
    );
  }

  @override
  bool shouldRepaint(covariant _SplitCanvasPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class ThisOrThatStageLabel extends StatelessWidget {
  const ThisOrThatStageLabel({
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
    final palette = ThisOrThatPalette.of(context);
    final effectiveColor = color ?? palette.mutedInk;
    return Semantics(
      label: text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: effectiveColor),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class ThisOrThatChoiceCard extends StatelessWidget {
  const ThisOrThatChoiceCard({
    super.key,
    required this.side,
    required this.text,
    required this.selected,
    this.emoji,
    this.onTap,
    this.compact = false,
    this.revealed = true,
    this.badge,
  }) : assert(side == 'a' || side == 'b');

  final String side;
  final String text;
  final bool selected;
  final String? emoji;
  final VoidCallback? onTap;
  final bool compact;
  final bool revealed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final isThis = side == 'a';
    final accent = isThis ? palette.thisColor : palette.thatColor;
    final surface = isThis ? palette.thisSurface : palette.thatSurface;
    final reduceMotion = reduceMotionOf(context);

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${isThis ? 'This' : 'That'}: $text',
      child: AnimatedScale(
        scale: selected ? 1 : 0.975,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? surface : palette.panel.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(compact ? 18 : 24),
            border: Border.all(
              color: selected ? accent : palette.line,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: selected ? 0.20 : 0.07),
                blurRadius: selected ? 22 : 8,
                offset: Offset(0, selected ? 8 : 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(compact ? 18 : 24),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 14 : 18,
                  vertical: compact ? 14 : 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          isThis ? 'THIS' : 'THAT',
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 10 : 16),
                    AnimatedSwitcher(
                      duration:
                          reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                      transitionBuilder:
                          (child, animation) => FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween(begin: 0.88, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                ),
                              ),
                              child: child,
                            ),
                          ),
                      child:
                          revealed
                              ? Column(
                                key: ValueKey('revealed-$text'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (emoji != null && emoji!.isNotEmpty) ...[
                                    Text(
                                      emoji!,
                                      style: TextStyle(
                                        fontSize: compact ? 32 : 46,
                                        height: 1,
                                      ),
                                    ),
                                    SizedBox(height: compact ? 8 : 14),
                                  ],
                                  Text(
                                    text,
                                    maxLines: compact ? 2 : 4,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge?.copyWith(
                                      color: palette.ink,
                                      fontSize: compact ? 17 : 21,
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              )
                              : Icon(
                                Icons.question_mark_rounded,
                                key: const ValueKey('hidden'),
                                size: compact ? 42 : 56,
                                color: accent,
                              ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThisOrThatPrimaryAction extends StatelessWidget {
  const ThisOrThatPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: palette.ink,
          foregroundColor: palette.canvas,
          disabledBackgroundColor: palette.line,
          disabledForegroundColor: palette.mutedInk,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        child:
            loading
                ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: palette.canvas,
                  ),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label),
                    const SizedBox(width: 8),
                    Icon(icon, size: 20),
                  ],
                ),
      ),
    );
  }
}

class ThisOrThatPartnerPresence extends StatelessWidget {
  const ThisOrThatPartnerPresence({
    super.key,
    required this.partnerName,
    required this.answered,
  });

  final String partnerName;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final color = answered ? palette.thisColor : palette.mutedInk;
    final duration =
        reduceMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 240);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.sizeOf(context).width * 0.52, 220),
      ),
      child: AnimatedContainer(
        duration: duration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.panel.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: duration,
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                answered ? '$partnerName picked' : '$partnerName is choosing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThisOrThatWaitingMark extends StatefulWidget {
  const ThisOrThatWaitingMark({super.key, this.size = 112});

  final double size;

  @override
  State<ThisOrThatWaitingMark> createState() => _ThisOrThatWaitingMarkState();
}

class _ThisOrThatWaitingMarkState extends State<ThisOrThatWaitingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _controller.stop();
      _controller.value = 0.18;
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
    final palette = ThisOrThatPalette.of(context);
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder:
            (context, _) => CustomPaint(
              painter: _WaitingMarkPainter(
                progress: _controller.value,
                thisColor: palette.thisColor,
                thatColor: palette.thatColor,
                lineColor: palette.line,
              ),
              child: Center(
                child: Icon(
                  Icons.favorite_rounded,
                  color: palette.ink,
                  size: widget.size * 0.27,
                ),
              ),
            ),
      ),
    );
  }
}

class _WaitingMarkPainter extends CustomPainter {
  const _WaitingMarkPainter({
    required this.progress,
    required this.thisColor,
    required this.thatColor,
    required this.lineColor,
  });

  final double progress;
  final Color thisColor;
  final Color thatColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.38;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = lineColor,
    );

    for (var i = 0; i < 2; i++) {
      final angle = (progress * math.pi * 2) + (i * math.pi);
      final position = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawCircle(
        position,
        size.shortestSide * 0.095,
        Paint()..color = i == 0 ? thisColor : thatColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaitingMarkPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.thisColor != thisColor ||
      oldDelegate.thatColor != thatColor;
}
