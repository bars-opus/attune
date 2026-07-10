import 'package:attune/core/utils/exports/export_screens.dart';

class OnboardingChoiceButton extends StatelessWidget {
  const OnboardingChoiceButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SelectionTile(
      title: title,
      subtitle: subtitle,
      isSelected: selected,
      selectedColor: colorScheme.primary,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: colorScheme.primary,
        size: IconSizes.md.r,
      ),
      borderRadius: BorderRadiusTokens.lgAll,
      onTap: onTap,
    );
  }
}
