// lib/features/settings/screens/language_screen.dart
import 'package:attune/features/settings/utility/settings_exports.dart';

/// Language selection screen for choosing the application's display language.
///
/// This screen allows users to select their preferred interface language from
/// supported options. It integrates with the app's localization system via
/// Riverpod providers to manage language state changes and loading states.
///
/// ## Screen Architecture
/// ```
/// ┌─────────────────────────────────────┐
/// │  AppBar: "Language"                 │
/// │  ← Back Button                      │
/// ├─────────────────────────────────────┤
/// │                                     │
/// │  [Header Section]                   │
/// │  • "Select Language" title          │
/// │  • Description text                 │
/// │  • Divider                          │
/// │                                     │
/// │  [Language List - Scrollable]       │
/// │  ┌─────────────────────────────┐   │
/// │  │  🇺🇸 English (selected)    ✓ │   │
/// │  ├─────────────────────────────┤   │
/// │  │  🇪🇸 Español               → │   │
/// │  ├─────────────────────────────┤   │
/// │  │  🇫🇷 Français              → │   │
/// │  └─────────────────────────────┘   │
/// │                                     │
/// │  [Footer Section]                   │
/// │  • "Use Device Language" button     │
/// │  • Help text                        │
/// │                                     │
/// └─────────────────────────────────────┘
/// ```
///
/// ## Key Features
/// - **Real-time language preview**: Immediately shows language change effects
/// - **Loading states**: Visual feedback during language switching
/// - **Device language sync**: Option to reset to system language
/// - **Flag display**: Shows country flags alongside language names
/// - **Native name display**: Shows language names in their native script
/// - **Selection feedback**: Clear visual indication of current selection
/// - **Responsive design**: Uses `ScreenUtil` for consistent scaling
///
/// ## State Management
/// Uses Riverpod providers for reactive state management:
/// - `localeNotifierProvider`: Current selected language
/// - `localeLoadingProvider`: Language switching loading state
/// - `LocaleNotifier`: Business logic for language changes
///
/// ## Usage
/// This screen is typically accessed from:
/// - Settings menu → Language option
/// - App first-launch onboarding flow
/// - Profile/account settings
///
/// ## Integration Example
/// ```dart
/// // Navigation to language screen
/// context.push(LanguageScreen.routeName);
///
/// // Or from settings item
/// SettingsItem(
///   config: SettingsConfig(
///     id: 'language',
///     title: 'Language',
///     subtitle: 'App display language',
///     icon: Icons.language,
///     type: SettingsItemType.navigation,
///     routeName: LanguageScreen.routeName,
///   ),
/// )
/// ```
class LanguageScreen extends ConsumerWidget {
  /// Route name for navigation to this screen.
  ///
  /// Use with your navigation solution (go_router, Navigator 2.0, etc.)
  /// Example: `context.push(LanguageScreen.routeName)`
  static const String routeName = '/settings/language';

  /// Creates a language selection screen.
  ///
  /// Uses `ConsumerWidget` from Riverpod to watch language state providers
  /// and rebuild when language selection or loading state changes.
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Access theme for consistent styling
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Watch language state providers (reactive updates)
    final currentLanguage = ref.watch(localeNotifierProvider);
    final isLoading = ref.watch(localeLoadingProvider);
    final notifier = ref.read(localeNotifierProvider.notifier);

    // Localization instance (may be null during language switch)
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      // AppBar with back navigation and transparent background
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with instructions and description
            _buildHeader(context, theme, colorScheme),

            // Scrollable list of available languages
            Expanded(
              child: _buildLanguageList(
                context,
                currentLanguage,
                notifier,
                isLoading,
              ),
            ),

            // Footer with "Use Device Language" action
            _buildFooter(context, theme, notifier),
          ],
        ),
      ),
    );
  }

  /// 📝 Build header section with instructions and description.
  ///
  /// Creates the informational section at the top of the screen with:
  /// - Section title ("Select Language")
  /// - Descriptive text explaining the language selection
  /// - Visual divider separating header from content
  ///
  /// Uses responsive spacing tokens and theme-aware colors for consistency.
  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // Localization instance (may update during rebuild)
    final loc = AppLocalizations.of(context)!;

    return Padding(
      // Responsive padding using design tokens
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.md.h,
        Spacing.lg.w,
        Spacing.md.h,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title with medium font weight
          Text(
            loc.languageItemSubtitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
              fontSize: 14.sp,
            ),
          ),

          // Small vertical gap
          Gap(Spacing.xs.h),

          // Descriptive text explaining language selection scope
          Text(
            loc.languageScreenSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12.sp,
              height: 1.5, // Improved readability with line height
            ),
          ),

          // Medium vertical gap before divider
          Gap(Spacing.md.h),

          // Visual separator between header and language list
          AppDivider(
          
          ),
        ],
      ),
    );
  }

  /// 📋 Build scrollable list of available languages.
  ///
  /// Creates a vertically scrollable list of `SelectionTile` widgets,
  /// each representing a supported language. Shows loading indicators
  /// during language switching and visual selection feedback.
  ///
  /// Returns `SizedBox.shrink()` if no languages are available (edge case).
  Widget _buildLanguageList(
    BuildContext context,
    AppLanguage currentLanguage,
    LocaleNotifier notifier,
    bool isLoading,
  ) {
    // Get list of supported languages from app configuration
    final languages = supportedLanguages;

    // Handle empty state (shouldn't happen in production)
    if (languages.isEmpty) {
      return SizedBox.shrink();
    }

    // List with physics for natural scrolling feel
    return ListView.separated(
      // Responsive padding matching header
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.lg.w,
        vertical: Spacing.sm.h,
      ),
      // Bouncy physics for iOS-like feel (adjust per platform if needed)
      physics: const BouncingScrollPhysics(),
      itemCount: languages.length,
      // Gap between language items using design token
      separatorBuilder: (context, index) => Gap(Spacing.sm.h),
      itemBuilder: (context, index) {
        final language = languages[index];
        // Check if this language is currently selected
        final isSelected = notifier.isLanguageSelected(language);

        // Use SelectionTile for consistent selection interface
        return SelectionTile(
          title: language.name, // Localized name (e.g., "English")
          subtitle: language.nativeName, // Native script (e.g., "English")
          // Flag emoji as leading visual identifier
          leading: Text(language.flag, style: TextStyle(fontSize: 20.sp)),
          isSelected: isSelected,
          isLoading: isLoading,
          // Trigger language change on tap
          onTap: () => notifier.changeLanguage(language),
        );
      },
    );
  }

  /// 🦶 Build footer with additional language actions.
  ///
  /// Creates the bottom section containing:
  /// - "Use Device Language" button to reset to system language
  /// - Help text explaining what the button does
  ///
  /// Separated from the list with a subtle top border for visual hierarchy.
  Widget _buildFooter(
    BuildContext context,
    ThemeData theme,
    LocaleNotifier notifier,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Container(
      // Responsive padding matching overall screen layout
      padding: EdgeInsets.all(Spacing.lg.w),
      // Top border for visual separation from language list
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.1),
            width: 1.h,
          ),
        ),
      ),
      child: Column(
        children: [
          // Outlined button for "Use Device Language" action
          AppButton(
            height: 45.h, // Consistent touch target height
            label: loc.languageScreeUseDeviceLang,
            onPressed: () => notifier.resetToDeviceLanguage(),
            borderRadius:
                BorderRadiusTokens.xlAll, // Extra-large rounded corners
            variant: ButtonVariant.outline, // Outlined style (not filled)
            size: ButtonSize.small,
            width: double.infinity, // Full width button
            outlineColor:
                colorScheme.primary, // Theme primary color for outline
            textColor: colorScheme.primary, // Theme primary color for text
          ),

          // Small gap between button and help text
          Gap(Spacing.sm.h),

          // Help text explaining the button's function
          Text(
            loc.languageScreeUseDeviceLangNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12.sp,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
