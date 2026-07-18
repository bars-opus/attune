import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';

/// Shared shell for every onboarding step. Renders as one card in the
/// continuous OnboardingDeckCard stack (see that file for the flip/peek
/// mechanics) — step widgets are unaware of the deck and just supply their
/// title/subtitle/content, same as before this became a card deck.
class OnboardingStepFrame extends StatelessWidget {
  const OnboardingStepFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = OnboardingDeckScope.of(context);
    return OnboardingDeckCard(
      title: title,
      subtitle: subtitle,
      stepIndex: scope.cardKey,
      accent: scope.accent,
      enableDeck: scope.enableDeck,
      child: child,
    );
  }
}
