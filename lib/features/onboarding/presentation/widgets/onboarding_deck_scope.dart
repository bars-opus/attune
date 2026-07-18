import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:flutter/widgets.dart';

/// Broadcasts the current deck "card identity" and accent down to whichever
/// step widget is on screen, so OnboardingStepFrame can drive the flip
/// animation without every step widget taking new constructor parameters.
///
/// [cardKey] must change exactly when the visible card should flip — for most
/// steps that's the outer step index, but the quiz advances a card per
/// question while staying on one outer step, so OnboardingFlow combines both
/// into one value (see _cardKeyFor).
class OnboardingDeckScope extends InheritedWidget {
  const OnboardingDeckScope({
    super.key,
    required this.cardKey,
    required this.accent,
    required this.enableDeck,
    required super.child,
  });

  final int cardKey;
  final OnboardingDeckAccent accent;

  /// True only for the attachment quiz — turns the fanned card stack on. Name,
  /// mode choice, anchors, and terminal steps render as plain cards.
  final bool enableDeck;

  static OnboardingDeckScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<OnboardingDeckScope>();
    assert(scope != null, 'OnboardingDeckScope.of() called with no scope above it');
    return scope!;
  }

  @override
  bool updateShouldNotify(OnboardingDeckScope oldWidget) =>
      cardKey != oldWidget.cardKey ||
      accent != oldWidget.accent ||
      enableDeck != oldWidget.enableDeck;
}
