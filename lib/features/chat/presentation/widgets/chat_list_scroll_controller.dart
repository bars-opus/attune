import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The chat message list's [ScrollController]. Its position can cancel a
/// content shift under the reader in the SAME layout pass that caused it,
/// so the frame that adds a message never paints the list moved (#32).
///
/// A running animateTo / ensureVisible (a DrivenScrollActivity) writes
/// ABSOLUTE pixels on every tick, so on its own it would overwrite any
/// offset correction on its next tick — this hold, or Flutter's correctBy
/// repairing the list's content origin once index 0 comes near (the hold
/// leaves that origin off by the height of the row just past the cache
/// band minus the arrival's). The position therefore carries a running
/// animateTo across every correction: toward the newest end it blends the
/// jump out over the remaining path, so the motion continues from the
/// corrected pixels at the same speed and still ends at the newest end, on
/// time; toward a row it shifts the whole path by the correction, so it
/// lands on that row.
///
/// Flutter's own origin repair is not visually neutral: with the origin
/// drifted up by D (index 0 computed above offset 0), the sliver re-zeroes
/// the content by D but moves the offset by less — by `-scrollOffset`
/// through correctBy, or not at all once the cache-adjusted scroll offset
/// is 0 (it simply lays index 0 at 0). That frame's content moves by the
/// difference: a one-frame stall in an animation, a hitch under a drag.
/// So every viewport layout that starts scrolled up pins the row being
/// read first ([pinRowBeingRead], before any sliver lays out), and the
/// position cancels whatever that row moved in the content beyond the
/// pixels sliver corrections already moved: no frame paints it moved.
///
/// Behaves exactly like a plain [ScrollController] until something sets
/// [layoutCorrection] / [onOffsetCorrection] or a correction lands
/// mid-animation.
class ChatListScrollController extends ScrollController {
  ChatListScrollController({super.debugLabel});

  /// Asked on every viewport layout, before the position accepts the new
  /// content dimensions: how far (in content pixels) the pinned row moved
  /// since it was pinned. Null when nothing is pinned or the row is gone.
  double? Function()? layoutCorrection;

  /// Called at the start of every viewport layout: pin the row being read
  /// if nothing is pinned (and the list is not at its newest end). Returns
  /// whether a row is pinned now.
  bool Function()? pinRowBeingRead;

  /// Whether a row is pinned right now. Asked by a sliver correction
  /// (correctBy, mid-layout), which counts against an existing pin but
  /// never takes one: arming there could pin the sliver's first child,
  /// whose offset the sliver has just re-zeroed.
  bool Function()? rowPinned;

  /// Moves the offset to [value] without a notification (correctPixels),
  /// carrying a running animateTo across the move like any other
  /// correction — a bottom-padding hold mid-animation does not hop the list
  /// on the animation's next tick. Requires exactly one attached position.
  void correctPixelsCarryingDrive(double value) {
    final position = this.position;
    if (position is _AnchoringScrollPosition) {
      position.correctPixelsCarryingDrive(value);
    } else {
      position.correctPixels(value);
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _AnchoringScrollPosition(
      owner: this,
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _AnchoringScrollPosition extends ScrollPositionWithSingleContext {
  _AnchoringScrollPosition({
    required this.owner,
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final ChatListScrollController owner;

  /// Below this a "shift" is floating-point noise, not a moved row.
  static const _minCorrection = 0.01;

  /// The running animateTo, while it is the position's activity.
  _Drive? _drive;

  /// Pixels moved by sliver corrections since the current pin was taken;
  /// the pinned row's content delta already includes them.
  double _correctedSincePin = 0;

  @override
  bool applyViewportDimension(double viewportDimension) {
    // First call of every viewport layout, before any sliver lays out: the
    // row offsets are still the ones last painted.
    if (hasPixels && !(owner.pinRowBeingRead?.call() ?? false)) {
      _correctedSincePin = 0;
    }
    return super.applyViewportDimension(viewportDimension);
  }

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    final done = super.animateTo(to, duration: duration, curve: curve);
    final running = activity;
    if (running is DrivenScrollActivity) {
      final newestEnd = hasContentDimensions ? minScrollExtent : 0.0;
      _drive = _Drive(
        running,
        to: to,
        towardNewestEnd: to <= newestEnd + _minCorrection,
        from: pixels,
      );
    }
    return done;
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // Any new activity (a drag, a fling, another animateTo — which re-arms
    // after this) ends the carried drive.
    _drive = null;
    super.beginActivity(newActivity);
  }

  @override
  double setPixels(double newPixels) {
    final drive = _drive;
    if (drive != null && identical(activity, drive.activity)) {
      return super.setPixels(drive.map(newPixels));
    }
    return super.setPixels(newPixels);
  }

  @override
  void correctBy(double correction) {
    final before = pixels;
    super.correctBy(correction);
    if (owner.rowPinned?.call() ?? false) {
      _correctedSincePin += correction;
    }
    _carryDrive(before);
  }

  /// correctPixels that a running animateTo follows (see
  /// [ChatListScrollController.correctPixelsCarryingDrive]).
  void correctPixelsCarryingDrive(double value) {
    final before = pixels;
    correctPixels(value);
    _carryDrive(before);
  }

  /// Re-bases a running animateTo onto the corrected pixels. Not a new
  /// animateTo: re-issuing would restart the curve (a burst of speed mid-
  /// flight), send fresh scroll start/end notifications, and complete the
  /// caller's `done` future early.
  void _carryDrive(double before) {
    final drive = _drive;
    if (drive == null || !identical(activity, drive.activity)) return;
    drive.rebase(before: before, corrected: pixels);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (hasPixels) {
      final alreadyMoved = _correctedSincePin;
      _correctedSincePin = 0;
      final rowMoved = owner.layoutCorrection?.call();
      final correction = rowMoved == null ? 0.0 : rowMoved - alreadyMoved;
      if (correction.abs() > _minCorrection) {
        // correctPixels, not jumpTo: no notification, a drag keeps running,
        // and returning false makes the viewport lay out again at the
        // corrected offset before anything is painted.
        final before = pixels;
        correctPixels(math.max(minScrollExtent, pixels + correction));
        _carryDrive(before);
        // The pin was consumed, and the viewport lays out again: pin anew
        // here, between passes (every sliver has finished laying out, so
        // the offsets read are settled), so a sliver correction in the next
        // pass (Flutter's origin repair) is still measured against a row.
        // Never inside correctBy itself, mid-layout.
        owner.pinRowBeingRead?.call();
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// A running animateTo's path, mapped so it survives offset corrections.
///
/// The activity keeps producing its own (uncorrected) values `v`; the
/// position paints `scale * v + shift`. Starts as the identity.
class _Drive {
  _Drive(
    this.activity, {
    required this.to,
    required this.towardNewestEnd,
    required double from,
  }) : _lastRaw = from;

  final DrivenScrollActivity activity;
  final double to;
  final bool towardNewestEnd;
  double _scale = 1;
  double _shift = 0;
  double _lastRaw;

  /// Toward the newest end, each correction `c` taken at raw value `r` is
  /// blended out along the rest of the path: `c * w(u)`, `u` = the share of
  /// the distance from `r` still to go, `w(u) = 2u - u²` (all of it at `r`,
  /// with zero slope there so the speed is continuous where the jump
  /// landed, and none of it at the end). Corrections land late in a drive
  /// (the origin repair fires about a cache extent from the end), so a
  /// shape that absorbs them mid-way (smoothstep) dips or bumps visibly.
  final List<({double c, double r})> _blends = [];

  double map(double raw) {
    _lastRaw = raw;
    return _painted(raw);
  }

  double _painted(double raw) {
    var painted = _scale * raw + _shift;
    for (final blend in _blends) {
      final u = (raw - to) / (blend.r - to);
      painted += blend.c * (2 * u - u * u);
    }
    return painted;
  }

  /// Pixels jumped from [before] to [corrected] without a tick.
  ///
  /// Toward the newest end: keep the end and the end time, and keep the
  /// speed continuous — the jump is blended out over the remaining path
  /// (shorter: it eases off sooner; longer: it eases off later). Only if
  /// that would reverse the motion before the end (a jump bigger than about
  /// half the distance left) does the rest of the path rescale instead.
  /// Toward a row: move the whole path with the content.
  void rebase({required double before, required double corrected}) {
    final remaining = _lastRaw - to;
    if (towardNewestEnd) {
      // Within half a pixel of the end the drive is landing anyway; a
      // shift there would move the end off the newest end.
      if (remaining.abs() <= 0.5) return;
      final jump = corrected - _painted(_lastRaw);
      _blends.add((c: jump, r: _lastRaw));
      if (!_monotoneToEnd()) {
        _blends.clear();
        _scale = (corrected - to) / remaining;
        _shift = to - _scale * to;
      }
    } else {
      _shift += corrected - before;
    }
  }

  /// Whether the rest of the path still moves toward the end at every step
  /// (sampled; the blends are smooth quadratics, so 32 steps are plenty).
  bool _monotoneToEnd() {
    const steps = 32;
    final span = _lastRaw - to;
    var previous = _painted(_lastRaw);
    for (var k = steps - 1; k >= 0; k--) {
      final next = _painted(to + span * k / steps);
      if ((previous - next) * span.sign <= 0) return false;
      previous = next;
    }
    return true;
  }
}

/// Pins one on-screen row of a [SliverList] by its position in the list's
/// CONTENT (its layout offset), not on screen, so a change the reader is
/// meant to see — their own scroll, a bottom-padding hold — is never undone.
class ChatListAnchor {
  GlobalKey? _key;
  double _layoutOffset = 0;

  /// Whether a row is pinned and waiting for the next layout.
  bool get isArmed => _key != null;

  @visibleForTesting
  GlobalKey? get debugPinnedKey => _key;

  /// The list's own sliver element under [position]'s Scrollable (the
  /// first [SliverMultiBoxAdaptorElement] below it; rows, and any
  /// scrollable inside one, sit deeper). Null before the list is built.
  /// Walks with [Element.visitChildren], which (unlike visitChildElements)
  /// is allowed while the tree builds — an arrival pins from
  /// didUpdateWidget.
  static SliverMultiBoxAdaptorElement? findListElement(
    ScrollPosition position,
  ) {
    final BuildContext context;
    try {
      context = position.context.storageContext;
    } catch (_) {
      return null;
    }
    if (!context.mounted || context is! Element) return null;
    final queue = <Element>[context];
    for (var i = 0; i < queue.length; i++) {
      final element = queue[i];
      if (element is SliverMultiBoxAdaptorElement) return element;
      element.visitChildren(queue.add);
    }
    return null;
  }

  /// [arm], among the rows [list] has built only: O(built rows) where
  /// [arm] over every loaded row is O(loaded) — after a far jump thousands
  /// are loaded while a screenful is built, and this runs on every layout
  /// while scrolled up. [keyOf] maps a built child's own widget key (the
  /// item's key, unwrapped from the list delegate's) to the row's
  /// GlobalKey, or null for a child that is not a row.
  bool armAmongBuilt(
    SliverMultiBoxAdaptorElement list,
    GlobalKey? Function(Key? rowKey) keyOf,
  ) {
    final rows = <GlobalKey>[];
    list.visitChildren((child) {
      var key = child.widget.key;
      // SliverChildBuilderDelegate wraps a keyed item in a KeyedSubtree
      // whose key is a ValueKey holding the item's own key.
      if (key is ValueKey<Key>) key = key.value;
      final row = keyOf(key);
      if (row != null) rows.add(row);
    });
    return arm(rows);
  }

  /// Pins the bottom-most visible row among [rows] (the one nearest the
  /// newest end): only a change BELOW it can move it, and below is exactly
  /// where arrivals land. Returns whether a row was pinned.
  bool arm(Iterable<GlobalKey> rows) {
    _key = null;
    GlobalKey? visible;
    var visibleOffset = double.infinity;
    GlobalKey? straddling;
    var straddlingOffset = double.negativeInfinity;
    for (final key in rows) {
      final slot = _slotOf(key);
      if (slot == null) continue;
      final (offset, sliver) = slot;
      final visibleFrom = sliver.constraints.scrollOffset;
      if (offset >= visibleFrom) {
        if (offset < visibleOffset) {
          visible = key;
          visibleOffset = offset;
        }
      } else if (offset > straddlingOffset) {
        straddling = key;
        straddlingOffset = offset;
      }
    }
    if (visible != null) {
      _key = visible;
      _layoutOffset = visibleOffset;
    } else if (straddling != null) {
      _key = straddling;
      _layoutOffset = straddlingOffset;
    }
    return _key != null;
  }

  /// How far the pinned row moved in the content since [arm], then unpins.
  /// Null when nothing is pinned or the row is gone (deleted, replaced by
  /// its server copy under a new key, or dropped by the sliver) — never a
  /// guess, so an unmeasurable pin cannot undo a correction.
  double? consume() {
    final key = _key;
    _key = null;
    if (key == null) return null;
    final slot = _slotOf(key);
    if (slot == null) return null;
    return slot.$1 - _layoutOffset;
  }

  void clear() => _key = null;

  /// The layout offset of the sliver child holding [key]'s row, and that
  /// sliver. Reads parent data only (never a child's size), so it is safe
  /// to call while the viewport is laying out. [Element.renderObject]
  /// rather than findRenderObject: mid-layout the row may sit deactivated
  /// (the sliver dropped it and has not rebuilt it yet), which
  /// findRenderObject asserts on; a dropped row is detached and reads null.
  static (double, RenderSliverMultiBoxAdaptor)? _slotOf(GlobalKey key) {
    final element = key.currentContext as Element?;
    RenderObject? node = element?.renderObject;
    while (node != null && node.parent is! RenderSliverMultiBoxAdaptor) {
      node = node.parent;
    }
    if (node == null || !node.attached) return null;
    final sliver = node.parent! as RenderSliverMultiBoxAdaptor;
    final parentData = node.parentData;
    if (parentData is! SliverMultiBoxAdaptorParentData) return null;
    final offset = parentData.layoutOffset;
    if (offset == null) return null;
    return (offset, sliver);
  }
}
