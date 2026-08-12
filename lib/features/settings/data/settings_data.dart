// lib/features/settings/data/settings_data.dart
import 'package:attune/features/auth/presentation/widgets/logout_action.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/presentation/widgets/end_relationship_action.dart';
import 'package:attune/features/settings/utility/settings_exports.dart';

class SettingsDataSource {
  static List<SettingsSection> getSettingsSections(
    BuildContext context,
    String currentUserId,
  ) {
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isAuthenticated = currentUserId.isNotEmpty;

    return [
      if (isAuthenticated)
        SettingsSection(
          id: 'account',
          title: '',
          items: [
            SettingsConfig(
              id: 'profile',
              title: loc.profileItemTitle,
              subtitle: loc.profileItemSubtitle,
              icon: Icons.person,
              type: SettingsItemType.navigation,
              routeName: '/profile',
              iconColor: theme.colorScheme.primary,
              order: 1,
            ),
            SettingsConfig(
              id: 'location',
              title: loc.locationItemTitle,
              subtitle: loc.locationItemSubtitle,
              icon: Icons.location_on,
              type: SettingsItemType.navigation,
              routeName: '/editLocation',
              onTap: () => context.push('/editLocation'),
              iconColor: Colors.green,
              order: 2,
            ),
            SettingsConfig(
              id: 'notifications',
              title: loc.notificationsItemTitle,
              subtitle: loc.notificationsItemSubtitle,
              icon: Icons.notifications,
              type: SettingsItemType.navigation,
              routeName: '/notifications',
              iconColor: Colors.orange,
              order: 3,
            ),
            SettingsConfig(
              id: 'blocked',
              title: loc.blockedItemTitle,
              subtitle: loc.blockedItemSubtitle,
              icon: Icons.block,
              type: SettingsItemType.navigation,
              routeName: '/blockedAccountsScreen',
              iconColor: Colors.red,
              order: 4,
            ),
            // Distinct from "blocked" above: block operates on real chat/
            // relationship identities, mute operates on the anonymous
            // forum's opaque author_handle and can never know who the muted
            // account actually is (FORUM.md §3) — the two cannot be merged,
            // so mute gets its own settings entry alongside block rather
            // than replacing it.
            SettingsConfig(
              id: 'muted',
              title: loc.mutedItemTitle,
              subtitle: loc.mutedItemSubtitle,
              icon: Icons.volume_off_outlined,
              type: SettingsItemType.navigation,
              routeName: '/mutedAuthorsScreen',
              iconColor: Colors.red,
              order: 5,
            ),
            SettingsConfig(
              id: 'qr_code',
              title: loc.qrCodeItemTitle,
              subtitle: loc.qrCodeItemSubtitle,
              icon: Icons.qr_code_2_rounded,
              type: SettingsItemType.navigation,
              iconColor: Colors.purple,
              order: 6,
            ),
            SettingsConfig(
              id: 'share_profile',
              title: loc.shareProfileItemTitle,
              subtitle: loc.shareProfileItemSubtitle,
              icon: Icons.share,
              url: 'https://yourapp.com/privacy',
              type: SettingsItemType.link,
              iconColor: Colors.blue,
              order: 7,
            ),
            // Relationship history, not a current-conversation feature — the
            // Chat tab's conversation list only ever shows the active
            // relationship (see CHAT_SYSTEM_SPEC.md §11.1); ended
            // relationships' read-only threads live here instead, alongside
            // the other relationship-lifecycle action (endRelationship,
            // below in the danger section).
            SettingsConfig(
              id: 'previous_relationships',
              title: 'Previous relationships',
              subtitle: 'Read-only chat history from past relationships',
              icon: Icons.history,
              type: SettingsItemType.navigation,
              routeName: '/previous-relationships',
              iconColor: Colors.grey,
              order: 8,
            ),
          ],
        ),
      SettingsSection(
        id: 'app',
        title: loc.appSettingsSectionTitle,
        subtitle: loc.appSettingsSectionSubtitle,
        items: [
          SettingsConfig(
            id: 'theme',
            title: loc.themeItemTitle,
            subtitle: loc.themeItemSubtitle,
            icon: Icons.dark_mode,
            type: SettingsItemType.navigation,
            routeName: '/theme',
            iconColor: Colors.grey,
            order: 1,
          ),
          SettingsConfig(
            id: 'language',
            title: loc.languageItemTitle,
            subtitle: loc.languageItemSubtitle,
            icon: Icons.language_outlined,
            type: SettingsItemType.navigation,
            onTap: () => context.push('/language'),
            iconColor: Colors.grey,
            order: 1,
            trailing: Consumer(
              builder: (context, ref, child) {
                final currentLanguage = ref.watch(localeNotifierProvider);
                return Text(
                  currentLanguage.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
          // SettingsConfig(
          //   id: 'biometric',
          //   title: loc.biometricItemTitle,
          //   subtitle: loc.biometricItemSubtitle,
          //   icon: Icons.fingerprint,
          //   type: SettingsItemType.toggle,
          //   value: true,
          //   onToggle: (value) => _handleBiometricToggle(context, value),
          //   iconColor: Colors.grey,
          //   order: 3,
          // ),
        ],
      ),
      SettingsSection(
        id: 'support',
        title: loc.supportSectionTitle,
        items: [
          SettingsConfig(
            id: 'guide',
            title: loc.guideItemTitle,
            subtitle: loc.guideItemSubtitle,
            icon: Icons.menu_book,
            onTap: () {},
            type: SettingsItemType.info,
            routeName: '/guide',
            iconColor: Colors.grey,
            order: 1,
          ),
          SettingsConfig(
            id: 'help',
            title: loc.helpItemTitle,
            subtitle: loc.helpItemSubtitle,
            icon: Icons.support_agent,
            type: SettingsItemType.link,
            url: AppConstants.whatAppCustomerSupportLink,
            iconColor: Colors.grey,
            order: 1,
          ),
          SettingsConfig(
            id: 'safety_resources',
            title: 'Safety resources',
            subtitle: 'Open support contacts and quick exit tools',
            icon: Icons.shield_outlined,
            type: SettingsItemType.navigation,
            routeName: '/safety-resources',
            iconColor: Colors.redAccent,
            order: 2,
          ),
          SettingsConfig(
            id: 'feedback',
            title: loc.feedbackItemTitle,
            subtitle: loc.feedbackItemSubtitle,
            icon: Icons.feedback,
            type: SettingsItemType.navigation,
            onTap: () {},
            iconColor: Colors.grey,
            order: 3,
          ),
          SettingsConfig(
            id: 'rate',
            title: loc.rateItemTitle,
            subtitle: loc.rateItemSubtitle,
            icon: Icons.star,
            type: SettingsItemType.link,
            url: 'https://yourapp.com/privacy',
            iconColor: Colors.grey,
            order: 3,
          ),
          SettingsConfig(
            id: 'appInfoScreen',
            title: loc.appInfoItemTitle(AppConstants.appName),

            subtitle: loc.appInfoItemSubtitle,
            icon: Icons.memory,
            type: SettingsItemType.navigation,
            routeName: '/appInfoScreen',
            iconColor: Colors.grey,
            order: 4,
          ),
        ],
      ),
      SettingsSection(
        id: 'legal',
        title: loc.legalSectionTitle,
        showDivider: false,
        items: [
          SettingsConfig(
            id: 'terms',
            title: loc.termsItemTitle,
            subtitle: loc.termsItemSubtitle,
            icon: Icons.description,
            type: SettingsItemType.info,
            routeName: '/terms',
            iconColor: Colors.grey,
            order: 1,
          ),
          SettingsConfig(
            id: 'licenses',
            title: loc.licensesItemTitle,
            subtitle: loc.licensesItemSubtitle,
            icon: Icons.code,
            type: SettingsItemType.navigation,
            routeName: '/licenses',
            iconColor: Colors.grey,
            order: 3,
          ),
        ],
      ),
      if (currentUserId.isNotEmpty)
        SettingsSection(
          id: 'danger',
          title: loc.accountActionsSectionTitle,
          items: [
            SettingsConfig(
              id: 'deactivate',
              title: loc.deactivateItemTitle,
              subtitle: loc.deactivateItemSubtitle,
              icon: Icons.person_off_outlined,
              type: SettingsItemType.action,
              onTap: () {},
              iconColor: Colors.grey,
              order: 1,
            ),
            SettingsConfig(
              id: 'delete',
              title: loc.deleteItemTitle,
              subtitle: loc.deleteItemSubtitle,
              icon: Icons.delete,
              type: SettingsItemType.destructive,
              onTap: () {},
              iconColor: Colors.red,
              order: 2,
            ),
            SettingsConfig(
              id: 'endRelationship',
              title: 'End relationship',
              subtitle: 'Permanently end your relationship on Attune',
              icon: Icons.heart_broken_outlined,
              type: SettingsItemType.destructive,
              onTap: () async {
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final relationshipId = await container.read(
                  activeRelationshipIdProvider.future,
                );
                if (relationshipId == null) {
                  if (context.mounted) {
                    context.showErrorSnackbar(
                      'No active relationship to end.',
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  EndRelationshipAction.confirmAndEnd(
                    context,
                    relationshipId: relationshipId,
                  );
                }
              },
              iconColor: theme.colorScheme.error,
              order: 0,
            ),
            SettingsConfig(
              id: 'logout',

              title: loc.logoutItemTitle,
              subtitle: loc.logoutItemSubtitle,
              icon: Icons.logout,
              type: SettingsItemType.destructive,
              onTap: () => LogoutAction.confirmAndSignOut(context),
              iconColor: theme.colorScheme.primary,
              order: 1,
            ),
          ],
        ),
    ];
  }
}
