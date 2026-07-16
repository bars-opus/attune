// lib/features/games/paint_ball/presentation/widgets/paint_ball_arena.dart

import 'dart:math' as math;

import 'package:attune/core/utils/exports/export_screens.dart';

class PaintBallArena extends StatefulWidget {
  final bool isMyTurn;
  final bool showHitFeedback;
  final bool showMissFeedback;
  final bool showKnockout;
  final ValueChanged<bool>? onFire;
  final bool isSubmitting;

  const PaintBallArena({
    super.key,
    required this.isMyTurn,
    this.showHitFeedback = false,
    this.showMissFeedback = false,
    this.showKnockout = false,
    this.onFire,
    this.isSubmitting = false,
  });

  @override
  State<PaintBallArena> createState() => _PaintBallArenaState();
}

class _PaintBallArenaState extends State<PaintBallArena>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Reduce-motion (spec §8.4): keep the SAME tap-to-fire skill but slow the
  // sweep and widen the window so the game stays playable and fair without a
  // fast animation — never a coin-flip, which would strip the skill. Resolved
  // once, after the first frame, from MediaQuery.disableAnimations.
  bool _reduceMotion = false;
  bool _initialised = false;

  static const _sweepNormal = Duration(milliseconds: 1500);
  static const _sweepReduced = Duration(milliseconds: 2500);
  // Normal window ~24% of the sweep; reduced ~40% (wider = more forgiving).
  static const double _windowStartNormal = 0.38;
  static const double _windowEndNormal = 0.62;
  static const double _windowStartReduced = 0.30;
  static const double _windowEndReduced = 0.70;

  double get _hitWindowStart =>
      _reduceMotion ? _windowStartReduced : _windowStartNormal;
  double get _hitWindowEnd =>
      _reduceMotion ? _windowEndReduced : _windowEndNormal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _sweepNormal,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is only available here, not in initState. Apply reduce-motion
    // once so the sweep starts at the correct speed.
    if (_initialised) return;
    _initialised = true;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _controller.duration = _reduceMotion ? _sweepReduced : _sweepNormal;
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.isMyTurn || widget.isSubmitting) return;
    final progress = _controller.value;
    final hit = progress >= _hitWindowStart && progress <= _hitWindowEnd;
    widget.onFire?.call(hit);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.r),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final laneWidth = constraints.maxWidth - (Spacing.lg.w * 2);
                      final targetLeft = Spacing.lg.w + (laneWidth * _controller.value);
                      final targetInWindow =
                          _controller.value >= _hitWindowStart &&
                          _controller.value <= _hitWindowEnd;

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: Spacing.lg.w,
                                vertical: Spacing.lg.h,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildCoverRow(
                                    context,
                                    isOpponent: true,
                                    active: widget.isMyTurn,
                                  ),
                                  Gap(Spacing.lg.h * 2),
                                  Container(
                                    height: 2.h,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: colorScheme.outline.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(999.r),
                                    ),
                                  ),
                                  Gap(Spacing.lg.h * 2),
                                  _buildCoverRow(
                                    context,
                                    isOpponent: false,
                                    active: widget.isMyTurn,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: constraints.maxHeight * 0.48,
                            left: targetLeft - 16.w,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 32.w,
                              height: 32.w,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: targetInWindow
                                    ? colorScheme.primary
                                    : colorScheme.secondary,
                                boxShadow: [
                                  BoxShadow(
                                    color: (targetInWindow
                                            ? colorScheme.primary
                                            : colorScheme.secondary)
                                        .withValues(alpha: 0.25),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.radio_button_checked,
                                color: colorScheme.onPrimary,
                                size: 16.sp,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: widget.showHitFeedback ? 1 : 0,
                                duration: const Duration(milliseconds: 140),
                                child: Container(
                                  color: Colors.green.withValues(alpha: 0.22),
                                  child: Center(
                                    child: Text(
                                      'HIT',
                                      style: textTheme.headlineMedium?.copyWith(
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: widget.showMissFeedback ? 1 : 0,
                                duration: const Duration(milliseconds: 140),
                                child: Container(
                                  color: Colors.red.withValues(alpha: 0.18),
                                  child: Center(
                                    child: Text(
                                      'MISS',
                                      style: textTheme.headlineMedium?.copyWith(
                                        color: colorScheme.onPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: widget.showKnockout ? 1 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: Container(
                                  color: Colors.purple.withValues(alpha: 0.32),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'KNOCKOUT',
                                          style: textTheme.headlineMedium?.copyWith(
                                            color: colorScheme.onPrimary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Gap(Spacing.xs.h),
                                        Text(
                                          'Truth or dare time',
                                          style: textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: Spacing.md.h,
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: Spacing.md.w),
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.md.w,
                    vertical: Spacing.sm.h,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isMyTurn
                        ? colorScheme.primary.withValues(alpha: 0.08)
                        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(
                      color: widget.isMyTurn
                          ? colorScheme.primary.withValues(alpha: 0.25)
                          : colorScheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isMyTurn ? Icons.touch_app : Icons.schedule,
                        size: 18.sp,
                        color: widget.isMyTurn
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                      Gap(Spacing.sm.w),
                      Flexible(
                        child: Text(
                          widget.isMyTurn
                              ? widget.isSubmitting
                                  ? 'Shot resolving...'
                                  : 'Tap the arena to fire'
                              : 'Waiting for partner...',
                          textAlign: TextAlign.center,
                          style: textTheme.labelLarge?.copyWith(
                            color: widget.isMyTurn
                                ? colorScheme.primary
                                : colorScheme.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverRow(
    BuildContext context, {
    required bool isOpponent,
    required bool active,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isOpponent ? colorScheme.secondary : colorScheme.primary;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Container(
          margin: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
          width: 32.w,
          height: 32.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: active ? 0.88 : 0.72),
            border: Border.all(
              color: color.withValues(alpha: 0.9),
              width: 1.5.r,
            ),
          ),
          child: Center(
            child: Transform.rotate(
              angle: isOpponent ? math.pi : 0,
              child: Icon(
                Icons.change_history,
                size: 14.sp,
                color: colorScheme.onPrimary.withValues(alpha: 0.95),
              ),
            ),
          ),
        );
      }),
    );
  }
}
