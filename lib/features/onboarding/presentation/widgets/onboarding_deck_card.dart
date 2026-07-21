import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/animated_stepped_progress_bar.dart';

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
    this.icon = Icons.people,
    this.accent = OnboardingDeckAccent.neutral,
    this.enableDeck = false,
    this.progressValue = 0,
    this.totalSegments = 0,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final double progressValue;
  final int totalSegments;

  /// Shown in the header row. Each step picks whatever fits its content (a
  /// name field, a mode choice, the quiz, etc.) so the icon is dynamic per
  /// screen rather than the same glyph everywhere.
  final IconData icon;

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
  static const double _peekSliver =
      12.0; // vertical sliver each back card shows
  static const double _peekInset = 14.0; // horizontal shrink per card back

  // Stable identities for the two card ROLES that ride a SingleChildScrollView
  // (see _cardSurface). Every AnimatedBuilder frame rebuilds the Stack's
  // children, and the branch that runs (entering / rest / forward / reverse)
  // changes both the child COUNT and the geometry wrapper (Positioned.fill for
  // a flying card vs Positioned(height:) for a resting one). Without keys,
  // Flutter reconciles the Stack's children by index+type, so on the frame a
  // transition ends — entrance completing, or _outgoing being nulled — the
  // flying card's Positioned.fill element at the tail gets matched into the
  // resting card's Positioned(height:) at that same index. The shared
  // SingleChildScrollView render object is then reused with the previous
  // frame's constraints still in force and painted before it relays out, which
  // is exactly the "RenderBox was not laid out" cascade. Distinct keys pin each
  // role to its own element subtree, so a flying scroll view is never fused
  // into a resting one mid-frame — it cleanly unmounts and the resting one
  // mounts fresh instead.
  static const ValueKey<String> _frontSlotKey = ValueKey('deck-front-slot');
  static const ValueKey<String> _flyingCardKey = ValueKey('deck-flying-card');

  // --- advance motion timing ---
  static const Duration _advanceDuration = Duration(milliseconds: 900);
  // The entrance runs longer than a normal Next/Back advance — it's a
  // one-time first impression carrying 4 elements (3 peeks + the front
  // card), so it gets more room to read as slow and deliberate.
  static const Duration _entranceDuration = Duration(milliseconds: 900);

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
  // The entrance reuses this exact curve (and the exact _staggered wave) via
  // the `entering` branch below, which mirrors the REVERSE branch verbatim —
  // same wave, same settle, no separately-tuned entrance motion.
  static const Curve _settleCurve = Curves.easeOutCubic;
  //
  // _frontSettleCurve — the entrance's front card specifically: it lands
  // last and is the biggest, most-watched element, so it gets a heavier
  // decelerate than the peek cards' recede — noticeably slow and gentle at
  // the very end instead of just "no overshoot."
  static const Curve _frontSettleCurve = Curves.easeInOut;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _advanceDuration,
  );

  /// The card leaving the front slot, kept so it can animate away while the new
  /// one arrives. Null except during a transition.
  Widget? _outgoing;

  /// True when the visible step went BACKWARD (Back tapped). Thse whole motion
  /// mirrors: the incoming (previous) card drops in from the top and the
  /// current front recedes down into the stack, rather than flying off the top.
  bool _reverse = false;

  /// True only for the very first build of the quiz: the whole fanned stack
  /// rises up from below the screen and settles into place — the same rising
  /// motion the reverse (Back) transition uses for its incoming card, but
  /// applied to every card in the stack at once, staggered back-to-front, so
  /// the deck doesn't just pop into existence.
  bool _entering = false;

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
      if (status == AnimationStatus.completed) {
        if (_outgoing != null) setState(() => _outgoing = null);
        if (_entering) {
          setState(() => _entering = false);
          // Hand the controller back to the shorter per-advance timing.
          _controller.duration = _advanceDuration;
        }
      }
    });
    if (widget.enableDeck) {
      _entering = true;
      // Deferred so reduceMotionOf(context) (read in didChangeDependencies,
      // which runs before the first frame) has already been cached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _reduceMotion) {
          if (mounted) setState(() => _entering = false);
          return;
        }
        // Entrance plays the identical wave shape the REVERSE branch uses,
        // just with no receding front card and a longer duration so its
        // one-time deal-in reads as slow and deliberate.
        _controller.duration = _entranceDuration;
        _controller.forward(from: 0);
      });
    }
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
            icon: widget.icon,
            iconSize: 40.h,
            avatarRadius: 25.h,
            onTap: () {},
            disableTrailing: true,
            showAvatar: false,
            showDivider: false,
            showTrailingArrow: false,
          ),
          Gap(Spacing.lg),
          if (widget.progressValue != 0) ...[
            AnimatedSteppedProgressBar(
              totalSegments: widget.totalSegments,
              progressValue: widget.progressValue,
            ),
            Gap(Spacing.lg),
          ],

          // Headroom for the fanned stack to peek above the front card: just
          // enough for the slivers themselves, nothing more. Adding a full
          // Spacing.xl on top pushed the quiz card past the bottom of shorter
          // screens (390x844 overflowed by ~179px). Non-deck steps need no gap
          // at all — the header already separates them.
          if (widget.enableDeck) Gap((_peekSliver * _peekCount).h),
          Expanded(
            child:
                widget.enableDeck
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
            final entering = _entering && _controller.isAnimating;
            final children = <Widget>[];

            if (entering) {
              // ENTRANCE: every card starts ENLARGED at the front slot (depth
              // 0) and shrinks back into its resting stacked position as it
              // arrives — deepest card recedes first, front card stays put
              // (never recedes) so it lands last, on top. Reads as cards being
              // dealt outward from a single point rather than growing in from
              // nothing.
              const int dealCount = _peekCount + 1; // peeks + the front card

              for (int depth = _peekCount; depth >= 1; depth--) {
                final order =
                    _peekCount - depth; // depth 3 -> 0 (first) ... depth 1 -> 2
                final local = _dealt(t, order, dealCount);
                final recede = _settleCurve.transform(local);
                children.add(
                  _positionedPeek(
                    colorScheme: colorScheme,
                    frontHeight: frontHeight,
                    // depth 0 (enlarged, front-sized) -> depth (resting spot).
                    effectiveDepth: depth * recede,
                    // Depth-based dimming is a RESTING look; animating it
                    // alongside a big positional travel reads as a fade-in, so
                    // keep peek cards fully opaque while they arrive.
                    forceOpaque: true,
                  ),
                );
              }

              // Front card lands LAST, on top of the assembled stack. It rides
              // the FULL timeline (not a _dealt slice like the peeks) so it
              // stays visibly slow the whole way rather than rushing through
              // a short final window — deepest arrives first, then each card
              // in front of it, then finally the live question eases in.
              children.add(
                _flyingFront(
                  colorScheme: colorScheme,
                  accentColor: accentColor,
                  progress: _frontSettleCurve.transform(t).clamp(0.0, 1.0),
                  exiting: false, // rising up from below
                  fallDistance: fallDistance,
                ),
              );
            } else if (!transitioning) {
              // At rest: the full fanned stack, back to front.
              for (int depth = _peekCount; depth >= 1; depth--) {
                children.add(
                  _positionedPeek(
                    colorScheme: colorScheme,
                    frontHeight: frontHeight,
                    effectiveDepth: depth.toDouble(),
                  ),
                );
              }
              children.add(
                _positionedCard(
                  key: _frontSlotKey,
                  frontHeight: frontHeight,
                  effectiveDepth: 0,
                  child: _cardSurface(colorScheme, accentColor, widget.child),
                  forceOpaque: true,
                ),
              );
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
                children.add(
                  _positionedPeek(
                    colorScheme: colorScheme,
                    frontHeight: frontHeight,
                    effectiveDepth: depth - fwd,
                  ),
                );
              }

              // Incoming front content (depth 1 -> 0), second-to-last in the wave.
              final incomingLocal = _staggered(t, (frontWave - 1) / frontWave);
              children.add(
                _positionedCard(
                  key: _frontSlotKey,
                  frontHeight: frontHeight,
                  effectiveDepth: 1 - _settleCurve.transform(incomingLocal),
                  child: _cardSurface(colorScheme, accentColor, widget.child),
                  forceOpaque: true,
                ),
              );

              // Falling front card: last in the wave, so it only takes off once
              // the push has rippled all the way forward.
              final fallLocal = _staggered(t, 1.0);
              children.add(
                _flyingFront(
                  colorScheme: colorScheme,
                  accentColor: accentColor,
                  progress: _fallCurve.transform(fallLocal),
                  exiting: true, // falling down off the bottom
                  fallDistance: fallDistance,
                ),
              );
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
                final fwd = _settleCurve.transform(_staggered(t, wavePos));
                children.add(
                  _positionedPeek(
                    colorScheme: colorScheme,
                    frontHeight: frontHeight,
                    effectiveDepth: depth + fwd,
                  ),
                );
              }

              // Current front receding into the stack (depth 0 -> 1), second in
              // the wave.
              final recedeLocal = _staggered(t, 1 / backWave);
              children.add(
                _positionedCard(
                  // The receding card carries the OUTGOING content, not the
                  // live front slot — it must reconcile against the forward
                  // branch's falling card (also _outgoing), so it shares the
                  // flying-card identity rather than the front-slot one.
                  key: _flyingCardKey,
                  frontHeight: frontHeight,
                  effectiveDepth: _settleCurve.transform(recedeLocal),
                  // Receding into the stack, never interactive again — same
                  // Hero-collision risk as the forward branch's outgoing
                  // card (see _flyingFront's HeroMode comment).
                  child: HeroMode(
                    enabled: false,
                    child: _cardSurface(colorScheme, accentColor, _outgoing!),
                  ),
                  forceOpaque: true,
                ),
              );

              // Previous content rising up from below into the front slot — first
              // in the wave (wavePos 0).
              final riseLocal = _staggered(t, 0.0);
              children.add(
                _flyingFront(
                  colorScheme: colorScheme,
                  accentColor: accentColor,
                  progress: _settleCurve.transform(riseLocal).clamp(0.0, 1.0),
                  exiting: false, // rising up from below
                  fallDistance: fallDistance,
                ),
              );
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

  /// Sequential deal: maps the global animation time [t] to a per-element
  /// local 0->1 for element [order] out of [count] (0 = dealt first, count-1
  /// = dealt last). Unlike [_staggered]'s heavily-overlapping push (right
  /// for a 2-element ripple where the back card visibly shoves the front one
  /// off), a 4-element entrance needs each card's arrival to be legible on
  /// its own — so windows overlap only slightly, enough to feel connected
  /// (each card is still moving as the next one starts) without the whole
  /// sequence collapsing into "front card alone, then the rest catch up."
  double _dealt(double t, int order, int count) {
    const overlap = 0.3; // fraction of a slot the next card starts early by
    final slot = 1.0 / (count - (count - 1) * overlap);
    final start = order * slot * (1.0 - overlap);
    return ((t - start) / slot).clamp(0.0, 1.0);
  }

  /// An empty decoration card positioned at a (fractional) depth. depth grows
  /// => smaller, higher, dimmer — unless [forceOpaque], used to keep cards
  /// fully visible while they're still travelling into place (see entrance).
  Widget _positionedPeek({
    required ColorScheme colorScheme,
    required double frontHeight,
    required double effectiveDepth,
    bool forceOpaque = false,
  }) {
    return _positionedCard(
      frontHeight: frontHeight,
      effectiveDepth: effectiveDepth,
      child: _peekSurface(colorScheme),
      forceOpaque: forceOpaque,
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
    Key? key,
  }) {
    // Wide enough to cover the entrance's start depth (depth + 3 travel units)
    // without clipping the beginning of its motion.
    final d = effectiveDepth.clamp(0.0, (_peekCount + 4).toDouble());
    final opacity = forceOpaque ? 1.0 : (1.0 - 0.22 * d).clamp(0.0, 1.0);
    return Positioned(
      key: key,
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
    final dy =
        exiting ? progress * fallDistance : (1 - progress) * fallDistance;
    final body = exiting ? _outgoing! : widget.child;
    // The outgoing card is a decorative snapshot falling off-screen, never
    // interactive again — but its content (the quiz card) can carry live
    // Hero-tagged widgets (see quiz_question_card.dart). If a question's
    // detail-view route was still resolving its own Hero flight when Next/
    // Finish was tapped, this card's Heroes and that flight's Heroes can
    // collide on the same tag while both are mounted, which corrupts layout
    // for the frame ("RenderBox was not laid out"). HeroMode(enabled: false)
    // makes every Hero in this subtree inert, so only the live, interactive
    // card's Heroes ever participate in a flight.
    final surface =
        exiting
            ? HeroMode(
              enabled: false,
              child: _cardSurface(colorScheme, accentColor, body),
            )
            : _cardSurface(colorScheme, accentColor, body);
    // Key by CONTENT identity, so the scroll subtree reconciles across branches
    // by the role it plays rather than by its Stack index: an EXITING card
    // (forward's falling _outgoing) shares the flying-card identity with the
    // reverse branch's receding _outgoing; an ARRIVING card (entrance / reverse
    // rising widget.child) shares the front-slot identity with the resting
    // front card. Without this, the arriving flying card's element would be
    // fused into the resting front card's element on the frame the animation
    // ends — reusing its SingleChildScrollView render object before it relays
    // out ("RenderBox was not laid out").
    return Positioned.fill(
      key: exiting ? _flyingCardKey : _frontSlotKey,
      child: Transform.translate(offset: Offset(0, dy), child: surface),
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

  /// The card surface that holds content. The CardInkWell chrome (border,
  /// shadow, ink response) is only used for the quiz stack — non-deck steps
  /// (name, mode choice, anchors, etc.) render their content plainly, with no
  /// card wrapper, since they were never meant to look like part of the stack.
  Widget _cardSurface(ColorScheme colorScheme, Color accentColor, Widget body) {
    final scrollable = LayoutBuilder(
      builder:
          (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: body,
            ),
          ),
    );

    if (!widget.enableDeck) {
      return scrollable;
    }

    // Inner padding is deliberately smaller than the frame's outer padding —
    // stacking two full-size paddings squeezed the content area enough to
    // overflow steps that rely on a Spacer.
    return CardInkWell(
      elevation: ElevationTokens.xl,

      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
        // Step content pins its action button to the bottom with a Spacer, which
        // needs a bounded height — but the content can exceed the card on
        // shorter screens. A scroll view whose child is forced to at least the
        // card height gives both: Spacer still works (the child is given a
        // tight-enough box), and anything taller scrolls instead of overflowing.
        child: scrollable,
      ),
    );
  }
}
