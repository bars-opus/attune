import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// Which accent the deck uses. Set once the user picks Single vs Couples
/// (OnboardingFlow._mode); [neutral] is used before that choice exists.
enum OnboardingDeckAccent { neutral, single, couples }

/// Shell for onboarding steps.
///
/// For the attachment quiz ([enableDeck] = true) it renders as a card STACK:
/// the front card is largest and holds the live question; behind it, cards fan
/// UP and BACK — each smaller and shifted higher so only a shrinking sliver
/// shows above the front card.
///
/// Advancing (stepIndex changes) plays one continuous motion: the old front
/// card flies UP and off the top (ease-in — gentle then accelerates away) while
/// every card behind it shifts one position FORWARD (grows + lowers + brightens,
/// ease-out-back so it settles with a hair of overshoot). A fresh card fades in
/// at the very back so the stack always looks full.
///
/// Non-quiz steps ([enableDeck] = false) render as a single plain card.
class OnboardingDeckCard extends StatefulWidget {
  const OnboardingDeckCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.stepIndex,
    this.accent = OnboardingDeckAccent.neutral,
    this.enableDeck = false,
  });

  final String title;
  final String subtitle;
  final Widget child;

  /// Changes exactly when the visible card should advance (the quiz folds its
  /// question index in here).
  final int stepIndex;

  final OnboardingDeckAccent accent;
  final bool enableDeck;

  @override
  State<OnboardingDeckCard> createState() => _OnboardingDeckCardState();
}

class _OnboardingDeckCardState extends State<OnboardingDeckCard>
    with SingleTickerProviderStateMixin {
  // --- stack geometry (tune to taste) ---
  static const int _peekCount = 3; // cards showing behind the front one
  static const double _peekSliver = 12.0; // vertical sliver each back card shows
  static const double _peekInset = 14.0; // horizontal shrink per card back

  // --- advance motion timing ---
  static const Duration _advanceDuration = Duration(milliseconds: 700);

  // Two curves, because falling and settling want opposite shapes:
  //
  // _fallCurve — the card DROPPING off the bottom. easeIn = gravity: it creeps,
  // then flings away. This is the "falling" feel. (Quart is very steep at the
  // tail; easeInCubic is the same character but smoother if Quart snaps.)
  static const Curve _fallCurve = Curves.easeInCubic;
  //
  // _settleCurve — anything ARRIVING/RESTING (back cards shifting forward, the
  // incoming card): easeOut so it decelerates and comes to rest smoothly rather
  // than accelerating into its spot (which is what made easeIn feel jittery).
  static const Curve _settleCurve = Curves.easeOutCubic;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _advanceDuration,
  );

  /// The card leaving the front slot, kept so it can animate away while the new
  /// one arrives. Null except during a transition.
  Widget? _outgoing;

  /// True when the visible step went BACKWARD (Back tapped). The whole motion
  /// mirrors: the incoming (previous) card drops in from the top and the
  /// current front recedes down into the stack, rather than flying off the top.
  bool _reverse = false;

  /// Cached from didChangeDependencies — reading MediaQuery in didUpdateWidget /
  /// dispose is unsafe (the element may be deactivating).
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    // Clear the outgoing card via a status listener rather than a
    // Future.whenComplete: the listener is torn down with the controller in
    // dispose(), so it can never fire against a deactivated element (which is
    // what triggered the "deactivated widget's ancestor" crash).
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _outgoing != null) {
        setState(() => _outgoing = null);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = reduceMotionOf(context);
  }

  @override
  void didUpdateWidget(covariant OnboardingDeckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableDeck &&
        widget.stepIndex != oldWidget.stepIndex &&
        !_reduceMotion) {
      _reverse = widget.stepIndex < oldWidget.stepIndex;
      _outgoing = oldWidget.child;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _accentColor(ColorScheme scheme) {
    switch (widget.accent) {
      case OnboardingDeckAccent.single:
        return scheme.primary;
      case OnboardingDeckAccent.couples:
        return Color.lerp(scheme.primary, scheme.info, 0.45) ?? scheme.primary;
      case OnboardingDeckAccent.neutral:
        return scheme.primary.withValues(alpha: 0.7);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accentColor = _accentColor(colorScheme);
    final reduceMotion = _reduceMotion;

    return Padding(
      padding: EdgeInsets.all(Spacing.lg.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          InfoRowWidget(
            subtitle: widget.subtitle,
            title: widget.title,
            icon: Icons.people,
            avatarRadius: 25.h,
            onTap: () {},
            disableTrailing: true,
            showAvatar: false,
            showTrailingArrow: false,
          ),
          // Headroom for the fanned stack to peek above the front card: just
          // enough for the slivers themselves, nothing more. Adding a full
          // Spacing.xl on top pushed the quiz card past the bottom of shorter
          // screens (390x844 overflowed by ~179px). Non-deck steps need no gap
          // at all — the header already separates them.
          if (widget.enableDeck) Gap((_peekSliver * _peekCount).h),
          Expanded(
            child: widget.enableDeck
                ? _buildDeck(colorScheme, accentColor, reduceMotion)
                : _cardSurface(colorScheme, accentColor, widget.child),
          ),
        ],
      ),
    );
  }

  Widget _buildDeck(
    ColorScheme colorScheme,
    Color accentColor,
    bool reduceMotion,
  ) {
    // Far enough that a falling card fully clears the bottom of the screen no
    // matter where the deck sits vertically.
    final fallDistance = MediaQuery.of(context).size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final frontHeight = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            // t: 0 at rest / start of advance, 1 when settled.
            final t = reduceMotion ? 1.0 : _controller.value;

            final transitioning = _controller.isAnimating && _outgoing != null;
            final children = <Widget>[];

            if (!transitioning) {
              // At rest: the full fanned stack, back to front.
              for (int depth = _peekCount; depth >= 1; depth--) {
                children.add(_positionedPeek(
                  colorScheme: colorScheme,
                  frontHeight: frontHeight,
                  effectiveDepth: depth.toDouble(),
                ));
              }
              children.add(_positionedCard(
                frontHeight: frontHeight,
                effectiveDepth: 0,
                child: _cardSurface(colorScheme, accentColor, widget.child),
                forceOpaque: true,
              ));
            } else if (!_reverse) {
              // FORWARD with a back-to-front RIPPLE: each card starts its shift a
              // beat AFTER the one behind it, so the push visibly travels up the
              // stack and finally launches the front card off the bottom.
              //
              // wavePos 0 = deepest card (moves first), 1 = falling front card
              // (moves last). _staggered() shifts+renormalizes the global t so
              // each card runs its own slice with generous overlap.
              const int frontWave = _peekCount + 1; // falling card is last

              // Back cards: depth _peekCount+1 .. 2 slide forward (depth->depth-1).
              for (int depth = _peekCount + 1; depth >= 2; depth--) {
                // Deeper card => earlier in the wave (smaller wavePos).
                final wavePos = (frontWave - depth) / frontWave;
                final local = _staggered(t, wavePos);
                final fwd = _settleCurve.transform(local);
                children.add(_positionedPeek(
                  colorScheme: colorScheme,
                  frontHeight: frontHeight,
                  effectiveDepth: depth - fwd,
                ));
              }

              // Incoming front content (depth 1 -> 0), second-to-last in the wave.
              final incomingLocal =
                  _staggered(t, (frontWave - 1) / frontWave);
              children.add(_positionedCard(
                frontHeight: frontHeight,
                effectiveDepth: 1 - _settleCurve.transform(incomingLocal),
                child: _cardSurface(colorScheme, accentColor, widget.child),
                forceOpaque: true,
              ));

              // Falling front card: last in the wave, so it only takes off once
              // the push has rippled all the way forward.
              final fallLocal = _staggered(t, 1.0);
              children.add(_flyingFront(
                colorScheme: colorScheme,
                accentColor: accentColor,
                progress: _fallCurve.transform(fallLocal),
                exiting: true, // falling down off the bottom
                fallDistance: fallDistance,
              ));
            } else {
              // REVERSE (Back) with a mirrored FRONT-TO-BACK ripple: the rising
              // card arrives first, then the recede + the back-card shifts follow
              // in sequence, so the wave travels front->back (the reverse of the
              // forward push).
              //
              // wavePos 0 = the rising incoming card (moves first);
              // deeper cards get a larger wavePos (move later).
              const int backWave = _peekCount + 1;

              // Deepest first for correct paint order, but each samples its own
              // staggered slice. depth d recedes one step: d -> d+1.
              for (int depth = _peekCount; depth >= 1; depth--) {
                final wavePos = (depth + 1) / backWave; // deeper => later
                final fwd =
                    _settleCurve.transform(_staggered(t, wavePos));
                children.add(_positionedPeek(
                  colorScheme: colorScheme,
                  frontHeight: frontHeight,
                  effectiveDepth: depth + fwd,
                ));
              }

              // Current front receding into the stack (depth 0 -> 1), second in
              // the wave.
              final recedeLocal = _staggered(t, 1 / backWave);
              children.add(_positionedCard(
                frontHeight: frontHeight,
                effectiveDepth: _settleCurve.transform(recedeLocal),
                child: _cardSurface(colorScheme, accentColor, _outgoing!),
                forceOpaque: true,
              ));

              // Previous content rising up from below into the front slot — first
              // in the wave (wavePos 0).
              final riseLocal = _staggered(t, 0.0);
              children.add(_flyingFront(
                colorScheme: colorScheme,
                accentColor: accentColor,
                progress: _settleCurve.transform(riseLocal).clamp(0.0, 1.0),
                exiting: false, // rising up from below
                fallDistance: fallDistance,
              ));
            }

            return Stack(clipBehavior: Clip.none, children: children);
          },
        );
      },
    );
  }

  /// Back-to-front ripple. Maps the global animation time [t] to a per-card
  /// local 0->1, delayed by the card's [wavePos] (0 = deepest, moves first;
  /// 1 = front/falling card, moves last). Windows overlap heavily so the push
  /// feels like one continuous wave, not discrete steps.
  double _staggered(double t, double wavePos) {
    // Smaller window => each card occupies less of the timeline => more
    // separation between cards => a stronger, more visible ripple.
    const windowWidth = 0.55;
    final start = wavePos.clamp(0.0, 1.0) * (1.0 - windowWidth);
    return ((t - start) / windowWidth).clamp(0.0, 1.0);
  }

  /// An empty decoration card positioned at a (fractional) depth. depth grows
  /// => smaller, higher, dimmer.
  Widget _positionedPeek({
    required ColorScheme colorScheme,
    required double frontHeight,
    required double effectiveDepth,
  }) {
    return _positionedCard(
      frontHeight: frontHeight,
      effectiveDepth: effectiveDepth,
      child: _peekSurface(colorScheme),
      forceOpaque: false,
    );
  }

  /// Positions any card at a (possibly fractional) depth: depth 0 = full front
  /// slot; larger = inset (smaller), raised (sliver), and — unless [forceOpaque]
  /// — dimmer.
  Widget _positionedCard({
    required double frontHeight,
    required double effectiveDepth,
    required Widget child,
    required bool forceOpaque,
  }) {
    final d = effectiveDepth.clamp(0.0, (_peekCount + 1).toDouble());
    final opacity = forceOpaque ? 1.0 : (1.0 - 0.22 * d).clamp(0.0, 1.0);
    return Positioned(
      top: -_peekSliver * d,
      left: _peekInset * d,
      right: _peekInset * d,
      height: frontHeight,
      child: Opacity(opacity: opacity, child: child),
    );
  }

  /// A full-size card that either falls DOWN off the bottom of the screen
  /// ([exiting] = forward's old card) or rises back UP from below into the front
  /// slot ([exiting] = false, reverse's incoming previous card). No fade, no
  /// scale — it just travels vertically and is clipped by the screen edge.
  /// [progress] runs 0 -> 1; [fallDistance] is far enough to clear the screen.
  Widget _flyingFront({
    required ColorScheme colorScheme,
    required Color accentColor,
    required double progress,
    required bool exiting,
    required double fallDistance,
  }) {
    // Exiting: 0 (in place) -> +fallDistance (down and off the bottom).
    // Arriving: +fallDistance (below) -> 0 (settled into the front slot).
    final dy = exiting ? progress * fallDistance : (1 - progress) * fallDistance;
    final body = exiting ? _outgoing! : widget.child;
    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(0, dy),
        child: _cardSurface(colorScheme, accentColor, body),
      ),
    );
  }

  /// A back-of-stack card: rounded surface only, no content.
  Widget _peekSurface(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.lg.r),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  /// The card surface that holds content (front card, or a plain non-deck step).
  /// Inner padding is deliberately smaller than the frame's outer padding —
  /// stacking two full-size paddings squeezed the content area enough to
  /// overflow steps that rely on a Spacer (profile setup, mode choice).
  Widget _cardSurface(ColorScheme colorScheme, Color accentColor, Widget body) {
    return CardInkWell(
      elevation: ElevationTokens.lg,
      child: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        // Step content pins its action button to the bottom with a Spacer, which
        // needs a bounded height — but the content can exceed the card on
        // shorter screens. A scroll view whose child is forced to at least the
        // card height gives both: Spacer still works (the child is given a
        // tight-enough box), and anything taller scrolls instead of overflowing.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}
