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
    this.icon = Icons.people,
    this.progressValue = 0,    this.totalSegments = 0,

  });

  final String title;
  final String subtitle;  final int totalSegments;

  final double progressValue;
  final Widget child;

  /// Each step passes an icon that fits its content, so the header stays
  /// dynamic per screen instead of showing the same glyph everywhere.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scope = OnboardingDeckScope.of(context);
    return OnboardingDeckCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      progressValue: progressValue,
      totalSegments:totalSegments,
      stepIndex: scope.cardKey,
      accent: scope.accent,
      enableDeck: scope.enableDeck,
      child: child,
    );
  }
}
