// The liquid selection lens: a small glass drop behind the selected item of
// a bar. When the selection moves, its leading edge runs ahead and its
// trailing edge follows, so the drop stretches across, thins a little in
// the middle of the move and gathers itself back at the new item, with a
// slight overshoot. With reduce motion it simply moves.
import 'dart:math' as math;

import 'package:attune/core/ui/glass/liquid_glass.dart';
import 'package:flutter/material.dart';

class LiquidLensRow extends StatefulWidget {
  const LiquidLensRow({
    super.key,
    required this.selectedIndex,
    required this.itemKeys,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    this.tint,
  });

  final int selectedIndex;

  /// One key per item, on the widget whose box the lens should cover.
  final List<GlobalKey> itemKeys;

  /// The row of items (the lens paints behind it).
  final Widget child;

  /// How far the lens reaches past an item's box.
  final EdgeInsets padding;
  final Color? tint;

  @override
  State<LiquidLensRow> createState() => _LiquidLensRowState();
}

class _LiquidLensRowState extends State<LiquidLensRow> with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  final GlobalKey _stackKey = GlobalKey();
  Rect? _from;
  Rect? _to;

  static const Curve _lead = Cubic(0.25, 1.32, 0.42, 1);
  static const Curve _trail = Interval(0.12, 1, curve: Cubic(0.5, 0, 0.2, 1.08));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(jump: true));
  }

  @override
  void didUpdateWidget(LiquidLensRow old) {
    super.didUpdateWidget(old);
    final moved = old.selectedIndex != widget.selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure(jump: !moved));
  }

  Rect? _rectOf(int index) {
    if (index < 0 || index >= widget.itemKeys.length) return null;
    final item = widget.itemKeys[index].currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (item == null || stack == null || !item.hasSize || !item.attached) return null;
    final topLeft = item.localToGlobal(Offset.zero, ancestor: stack);
    final rect = widget.padding.inflateRect(topLeft & item.size);
    // A capsule, never a circle: at least half as wide again as it is tall.
    final minWidth = rect.height * 1.6;
    if (rect.width >= minWidth) return rect;
    return Rect.fromCenter(center: rect.center, width: minWidth, height: rect.height);
  }

  void _measure({required bool jump}) {
    if (!mounted) return;
    final target = _rectOf(widget.selectedIndex);
    if (target == null) return;
    if (jump || _to == null || MediaQuery.disableAnimationsOf(context)) {
      // Already headed there: a rebuild mid-move must not snap it (I5).
      if (target == _to) return;
      setState(() {
        _from = target;
        _to = target;
      });
      _move.value = 1;
      return;
    }
    if (target == _to) return;
    setState(() {
      _from = _current() ?? _to;
      _to = target;
    });
    _move.forward(from: 0);
  }

  Rect? _current() {
    final from = _from, to = _to;
    if (from == null || to == null) return to;
    final t = _move.value;
    if (t >= 1 || from == to) return to;
    final right = to.center.dx >= from.center.dx;
    final lead = _lead.transform(t);
    final trail = _trail.transform(t);
    final l = _lerp(from.left, to.left, right ? trail : lead);
    final r = _lerp(from.right, to.right, right ? lead : trail);
    final squeeze = math.sin(math.pi * t.clamp(0.0, 1.0)) * 0.12;
    final top = _lerp(from.top, to.top, lead);
    final bottom = _lerp(from.bottom, to.bottom, lead);
    final inset = (bottom - top) * squeeze / 2;
    return Rect.fromLTRB(math.min(l, r - 1), top + inset, math.max(r, l + 1), bottom - inset);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      key: _stackKey,
      // The row keeps the constraints it had before the lens came along.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _move,
          builder: (context, _) {
            final rect = _current();
            if (rect == null) return const SizedBox.shrink();
            return Positioned.fromRect(
              rect: rect,
              child: IgnorePointer(
                child: LiquidGlass(
                  variant: GlassVariant.clear,
                  tint: widget.tint ?? scheme.primary.withValues(alpha: 0.13),
                  refraction: rect.height * 0.28,
                  shadow: false,
                  child: const SizedBox.expand(),
                ),
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}
