import 'package:flutter/widgets.dart';

import 'motion_tokens.dart';
import 'reduce_motion.dart';

/// A column whose children animate as the list changes: a new child grows
/// open and fades in, a removed one fades out while its space closes, and
/// a child that changes place glides from where it was to where it now is.
///
/// Children are matched across rebuilds by their keys, which must be unique.
/// Moves are worked out before the frame is drawn, from each child's last
/// height, so nothing flashes at its new place first. With reduce motion on,
/// every change lands at once.
///
/// Universal: knows nothing about what the children are.
class AnimatedKeyedColumn extends StatefulWidget {
  const AnimatedKeyedColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<AnimatedKeyedColumn> createState() => _AnimatedKeyedColumnState();
}

class _Entry {
  _Entry(this.key, this.widget, {required this.presence, required this.move});

  final Key key;
  Widget widget;

  /// 0 = not there (or gone), 1 = fully open.
  final AnimationController presence;
  late final CurvedAnimation opening = CurvedAnimation(parent: presence, curve: kMakeRoomCurve);

  /// 0 = at [from] (its old place), 1 = settled.
  final AnimationController move;
  Offset from = Offset.zero;
  bool leaving = false;

  /// Measures the child at its full height (inside the size transition).
  final GlobalKey measure = GlobalKey();
  double height = 0;

  double get openHeight => height * presence.value;
  double translateY(double t) => from.dy * (1 - t);

  void dispose() {
    opening.dispose();
    presence.dispose();
    move.dispose();
  }
}

class _AnimatedKeyedColumnState extends State<AnimatedKeyedColumn> with TickerProviderStateMixin {
  late List<_Entry> _entries = [for (final c in widget.children) _create(c, shown: true)];

  _Entry _create(Widget child, {required bool shown}) {
    assert(child.key != null, 'AnimatedKeyedColumn children need keys');
    return _Entry(
      child.key!,
      child,
      presence: AnimationController(vsync: this, duration: kMakeRoomDuration, value: shown ? 1 : 0),
      move: AnimationController(vsync: this, duration: kReorderDuration, value: 1),
    );
  }

  @override
  void didUpdateWidget(AnimatedKeyedColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    final instant = reduceMotionOf(context);
    final old = _entries;

    // Where each child is on screen right now: its place in the column so
    // far, plus any move still in progress.
    final visualTop = <Key, double>{};
    var top = 0.0;
    for (final e in old) {
      visualTop[e.key] = top + e.translateY(kReorderCurve.transform(e.move.value));
      top += e.openHeight;
    }

    final byKey = {for (final e in old) e.key: e};
    final next = <_Entry>[];
    final created = <_Entry>{};
    for (final child in widget.children) {
      var e = byKey.remove(child.key);
      if (e == null) {
        e = _create(child, shown: instant);
        created.add(e);
        if (!instant) e.presence.forward();
      } else {
        e.widget = child;
        if (e.leaving) {
          e.leaving = false; // put back (Undo) while it was leaving
          e.presence.forward();
        }
      }
      next.add(e);
    }

    // What's no longer listed leaves from where it was.
    for (final gone in byKey.values) {
      if (instant) {
        gone.dispose();
        continue;
      }
      if (!gone.leaving) {
        gone.leaving = true;
        gone.presence.reverse().then((_) {
          if (!mounted || !gone.leaving) return;
          setState(() => _entries.remove(gone));
          gone.dispose();
        });
      }
      final i = old.indexOf(gone);
      final before = old.take(i).toList().reversed.where(next.contains);
      next.insert(before.isEmpty ? 0 : next.indexOf(before.first) + 1, gone);
    }

    // Each child that stays glides from where it was to its new place.
    top = 0;
    for (final e in next) {
      final from = visualTop[e.key];
      if (!created.contains(e) && from != null && !instant && (from - top).abs() > 0.5) {
        e.from = Offset(0, from - top);
        e.move
          ..value = 0
          ..forward();
      } else if (instant || from == null) {
        e.from = Offset.zero;
        e.move.value = 1;
      }
      top += created.contains(e) ? 0 : e.openHeight;
    }
    _entries = next;
  }

  /// Keeps each child's full height for working out the next move.
  void _remeasure() {
    for (final e in _entries) {
      final box = e.measure.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) e.height = box.size.height;
    }
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _remeasure();
    });
    return Column(
      crossAxisAlignment: widget.crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in _entries)
          KeyedSubtree(
            key: ObjectKey(e),
            child: AnimatedBuilder(
              animation: e.move,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, e.translateY(kReorderCurve.transform(e.move.value))),
                child: child,
              ),
              child: SizeTransition(
                sizeFactor: e.opening,
                axisAlignment: -1,
                child: FadeTransition(
                  opacity: e.presence,
                  child: KeyedSubtree(key: e.measure, child: e.widget),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
