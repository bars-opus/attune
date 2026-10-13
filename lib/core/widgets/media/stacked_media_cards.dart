import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:flutter/material.dart';

/// The app's stacked-photos look, shared by chat albums and Planning photo
/// blocks: the front card swipes between items, up to three tilted cards sit
/// behind it, and a "2 / 5" counter rides on the photos.
///
/// Callers supply only what is inside each card ([itemBuilder]); the card
/// shape, border, tilt and counter are the same everywhere.
class StackedMediaCards extends StatefulWidget {
  const StackedMediaCards({
    super.key,
    required this.itemCount,
    required this.itemKey,
    required this.itemBuilder,
    required this.borderColor,
    required this.backColor,
    this.alignEnd = false,
    this.peekBehind = false,
    this.onTap,
    this.onFrontChanged,
  }) : assert(itemCount > 0);

  final int itemCount;

  /// A stable identity per item, so the front card stays on the same item
  /// when the list changes underneath it.
  final Object Function(int index) itemKey;

  /// What fills a card. It is sized and clipped to the card.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// The front card's border.
  final Color borderColor;

  /// The fill of the cards behind it.
  final Color backColor;

  /// Stacks toward the end edge (a sent chat album) instead of the start.
  final bool alignEnd;

  /// A real deck: the cards beneath the front one show the next items
  /// (wrapping round), and a swipe deals the front card off to reveal the
  /// one beneath, or brings the previous one back on top. Off, the cards
  /// beneath are plain and the items slide past as pages (chat albums).
  final bool peekBehind;

  final void Function(int index)? onTap;

  /// Which item is in front, after each swipe.
  final ValueChanged<int>? onFrontChanged;

  @override
  State<StackedMediaCards> createState() => _StackedMediaCardsState();
}

class _StackedMediaCardsState extends State<StackedMediaCards>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  var _frontIndex = 0;

  /// The deck's swipe: 0 at rest, toward -1 as the front card is dealt off
  /// to the left, toward 1 as the previous card comes back from the left.
  late final AnimationController _swipe;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _swipe = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(covariant StackedMediaCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIndex = _frontIndex.clamp(0, oldWidget.itemCount - 1);
    final previousKey = oldWidget.itemKey(previousIndex);
    var nextIndex = -1;
    for (var i = 0; i < widget.itemCount; i++) {
      if (widget.itemKey(i) == previousKey) {
        nextIndex = i;
        break;
      }
    }
    final resolvedIndex = nextIndex == -1 ? 0 : nextIndex;
    if (resolvedIndex == _frontIndex) return;
    _frontIndex = resolvedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(_frontIndex);
      }
    });
  }

  @override
  void dispose() {
    _swipe.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Widget _counter() => PositionedDirectional(
    key: const ValueKey('stacked-media-counter'),
    top: 20,
    // Inset from the edge rather than tight to it: it sits ON the photos,
    // and a chip flush to the corner reads as clipped rather than placed.
    end: widget.alignEnd ? null : 12,
    start: widget.alignEnd ? 12 : null,
    child: _CountBadge(current: _frontIndex + 1, total: widget.itemCount),
  );

  bool get _isDeck => widget.peekBehind && widget.itemCount > 1;

  int _wrap(int i) => i % widget.itemCount;

  // ---- the deck --------------------------------------------------------------

  static const _cardWidth = 238.0;

  void _onDragUpdate(DragUpdateDetails d) {
    _swipe.stop();
    _swipe.value = (_swipe.value + d.primaryDelta! / _cardWidth).clamp(
      -1.0,
      1.0,
    );
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    final p = _swipe.value;
    final target =
        (p <= -0.35 || v < -700)
            ? -1.0
            : (p >= 0.35 || v > 700)
            ? 1.0
            : 0.0;
    await _settle(target);
  }

  /// Animates the swipe to [target], then makes the dealt card the front.
  Future<void> _settle(double target) async {
    final instant = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final distance = (target - _swipe.value).abs();
    if (instant || distance == 0) {
      _swipe.value = target;
    } else {
      // Material's emphasized decelerate: it leaves the finger at speed
      // and glides into place over a long, soft tail.
      await _swipe.animateTo(
        target,
        duration: Duration(
          milliseconds: (500 * (0.6 + 0.4 * distance)).round(),
        ),
        curve: Easing.emphasizedDecelerate,
      );
    }
    if (!mounted || target == 0) return;
    setState(() => _frontIndex = _wrap(_frontIndex + (target < 0 ? 1 : -1)));
    _swipe.value = 0;
    widget.onFrontChanged?.call(_frontIndex);
  }

  /// One card at a continuous depth: 0 is the front, 1–3 the cards beneath.
  Widget _deckCard(
    int index, {
    required double depth,
    double opacity = 1,
    Offset fling = Offset.zero,
    double flingAngle = 0,
  }) {
    final side = widget.alignEnd ? -1.0 : 1.0;
    final offset = depth * 7.0;
    return Align(
      key: ValueKey(widget.itemKey(index)),
      alignment: widget.alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(side * offset, offset * 0.55) + fling,
          child: Transform.rotate(
            angle: side * depth * 0.018 + flingAngle,
            child: _DeckCard(
              front: depth < 0.5,
              borderColor: widget.borderColor,
              color: widget.backColor,
              child: widget.itemBuilder(context, index),
            ),
          ),
        ),
      ),
    );
  }

  /// The card being dealt off, or brought back: [t] is 0 on top of the deck
  /// and 1 fully off to the left.
  Widget _flungCard(int index, double t) => _deckCard(
    index,
    depth: 0,
    fling: Offset(-t * (_cardWidth + 40), -t * 18),
    flingAngle: -t * 0.22,
  );

  Widget _buildDeck(BuildContext context) {
    final n = widget.itemCount;
    final depth = (n - 1).clamp(1, 3);
    return Semantics(
      value: '${_frontIndex + 1} of $n',
      increasedValue: '${_wrap(_frontIndex + 1) + 1} of $n',
      decreasedValue: '${_wrap(_frontIndex - 1) + 1} of $n',
      onIncrease: () => _settle(-1),
      onDecrease: () => _settle(1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onTap: widget.onTap == null ? null : () => widget.onTap!(_frontIndex),
        child: SizedBox(
          width: 258,
          height: 318,
          child: AnimatedBuilder(
            animation: _swipe,
            builder: (context, _) {
              final p = _swipe.value;
              final cards = <Widget>[];
              if (p <= 0) {
                // Dealing the front card off: each card beneath moves up one,
                // and a new one fades in at the bottom.
                final t = -p;
                for (var layer = depth + 1; layer >= 1; layer--) {
                  if (layer > n - 1) continue;
                  cards.add(
                    _deckCard(
                      _wrap(_frontIndex + layer),
                      depth: layer - t,
                      opacity: layer > depth ? t : 1,
                    ),
                  );
                }
                cards.add(_flungCard(_frontIndex, t));
              } else {
                // Bringing the previous card back: the deck drops back one,
                // its bottom card fading out, and the previous card lands on top.
                final t = p;
                final incoming = _wrap(_frontIndex - 1);
                for (var layer = depth; layer >= 0; layer--) {
                  final index = _wrap(_frontIndex + layer);
                  if (index == incoming) continue; // it is the one coming back
                  cards.add(
                    _deckCard(
                      index,
                      depth: layer + t,
                      opacity: layer == depth && depth < n - 1 ? 1 - t : 1,
                    ),
                  );
                }
                cards.add(_flungCard(incoming, 1 - t));
              }
              return Stack(
                clipBehavior: Clip.none,
                alignment:
                    widget.alignEnd
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                children: [...cards, _counter()],
              );
            },
          ),
        ),
      ),
    );
  }

  int get _visibleBackLayers =>
      widget.itemCount <= 1 ? 0 : (widget.itemCount - 1).clamp(1, 3);

  @override
  Widget build(BuildContext context) {
    if (_isDeck) return _buildDeck(context);
    final stackAlignment =
        widget.alignEnd ? Alignment.centerRight : Alignment.centerLeft;
    return SizedBox(
      width: 258,
      height: 318,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: stackAlignment,
        children: [
          for (var layer = _visibleBackLayers; layer >= 1; layer--)
            _BackCard(
              key: ValueKey('stacked-media-back-card-$layer'),
              layer: layer,
              alignEnd: widget.alignEnd,
              color: widget.backColor,
              child:
                  widget.peekBehind
                      ? widget.itemBuilder(
                        context,
                        (_frontIndex + layer) % widget.itemCount,
                      )
                      : null,
            ),
          // Keyed so it keeps its element (and its one controller) as back
          // cards come and go beside it.
          PageView.builder(
            key: const ValueKey('stacked-media-pages'),
            controller: _pageController,
            itemCount: widget.itemCount,
            physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
            onPageChanged: (index) {
              if (_frontIndex != index) {
                setState(() => _frontIndex = index);
                widget.onFrontChanged?.call(index);
              }
            },
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  final page =
                      _pageController.positions.length == 1
                          ? (_pageController.page ?? _frontIndex.toDouble())
                          : _frontIndex.toDouble();
                  final distance = (page - index).clamp(-1.0, 1.0);
                  final scale = 1 - (distance.abs() * 0.035);
                  return Transform.rotate(
                    angle: distance * 0.018,
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: Align(
                  alignment: stackAlignment,
                  child: _FrontCard(
                    borderColor: widget.borderColor,
                    onTap:
                        widget.onTap == null
                            ? null
                            : () => widget.onTap!(index),
                    child: widget.itemBuilder(context, index),
                  ),
                ),
              );
            },
          ),
          if (widget.itemCount > 1) _counter(),
        ],
      ),
    );
  }
}

class _BackCard extends StatelessWidget {
  const _BackCard({
    super.key,
    required this.layer,
    required this.alignEnd,
    required this.color,
    this.child,
  });

  final int layer;
  final bool alignEnd;
  final Color color;

  /// What shows on the card, when the stack peeks.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final offset = layer * 7.0;
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Transform.translate(
        offset: Offset(alignEnd ? -offset : offset, offset * 0.55),
        child: Transform.rotate(
          angle: (alignEnd ? -1 : 1) * layer * 0.018,
          child: Container(
            width: 238,
            height: 300,
            // The border is drawn over a photo, and the photo is clipped to
            // the card's corners.
            clipBehavior: child == null ? Clip.none : Clip.antiAlias,
            foregroundDecoration:
                child == null
                    ? null
                    : BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(22),
              border:
                  child != null
                      ? null
                      : Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                      ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FrontCard extends StatelessWidget {
  const _FrontCard({
    required this.borderColor,
    required this.onTap,
    required this.child,
  });

  final Color borderColor;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: 238,
          height: 300,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A card in the deck: the front one has the stack's border, the ones
/// beneath the faint outline the back cards have.
class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.front,
    required this.borderColor,
    required this.color,
    required this.child,
  });

  final bool front;
  final Color borderColor;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Container(
      width: 238,
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border:
            front
                ? Border.all(color: borderColor, width: 2)
                : Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
      ),
      child: child,
    );
  }
}

/// The "2 / 5" chip. Its fill and full rounding match chat's video
/// duration badge, so the chips on a photo read as one set.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      // The number rolls like an odometer as the front card changes.
      child: AnimatedRollingCounter(
        count: current,
        suffix: ' / $total',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
