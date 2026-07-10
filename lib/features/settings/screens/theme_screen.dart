import 'package:attune/features/settings/utility/settings_exports.dart';

class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Access theme for consistent styling
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final currentTheme = ref.watch(themeProvider);
    // Localization instance (may be null during language switch)
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: true,
        title: Text(
          loc.languageItemTitle,

          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withOpacity(0.8),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(Spacing.lg.w),
        children: [
          // Header
          Text(
            loc.languageScreenSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12.sp,
              height: 1.5, // Improved readability with line height
            ),
          ), // Medium vertical gap before divider
          Gap(Spacing.md.h),
          // Visual separator between header and language list
          AppDivider(),
          // Theme options
          ...AppThemeMode.values.map((theme) {
            return _ThemeOption(
              theme: theme,
              isSelected: currentTheme == theme,
              onTap: () => ref.read(themeProvider.notifier).setTheme(theme),
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final AppThemeMode theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: SelectionTile(
        title: theme.displayName,
        subtitle: '',

        leading: Container(
          padding: EdgeInsets.all(Spacing.sm.h), // Use design token
          decoration: BoxDecoration(
            border: Border.all(
              width: BorderWidthTokens.hairline, // Design token for border
              color: isSelected ? colorScheme.primary : Colors.grey,
            ),
            color: _getContainerColor(theme, isSelected, colorScheme, context),
            borderRadius: BorderRadius.circular(10.r), // Design token
          ),
          child: Icon(
            theme.icon,
            size: IconSizes.md.h, // Design token
            color: _getIconColor(theme, isSelected, colorScheme, context),
          ),
        ),
        isSelected: isSelected,
        onTap: onTap,
      ),
    );
  }
}

Color _getContainerColor(
  AppThemeMode theme,
  bool isSelected,
  ColorScheme colorScheme,
  BuildContext context,
) {
  if (isSelected) {
    return colorScheme.primary; // Your selected color
  }

  switch (theme) {
    case AppThemeMode.system:
      return Colors.grey; // Your system color
    case AppThemeMode.light:
      return Colors.white; // Your light color
    case AppThemeMode.dark:
      return Theme.of(context).brightness == Brightness.dark
          ? Colors
              .white // Your dark mode color
          : Colors.black; // Your light mode color for dark theme
  }
}

Color _getIconColor(
  AppThemeMode theme,
  bool isSelected,
  ColorScheme colorScheme,
  BuildContext context,
) {
  if (isSelected && theme == AppThemeMode.dark) {
    return Colors.black; // Your selected Dark theme icon color
  }

  if (isSelected) {
    return Colors.white; // Your selected Light/System icon color
  }

  if (theme == AppThemeMode.system) {
    return Colors.white; // Your unselected System icon color
  }

  if (theme != AppThemeMode.dark) {
    return Colors.grey; // Your unselected Light/other icon color
  }

  return Colors.white; // Your default fallback
}
