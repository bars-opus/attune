// lib/features/settings/data/settings_data.dart
import 'package:attune/features/auth/presentation/widgets/logout_action.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/presentation/widgets/end_relationship_action.dart';
import 'package:attune/features/relationships/presentation/widgets/pause_relationship_action.dart';
import 'package:attune/features/settings/utility/settings_exports.dart';
import 'package:attune/features/settings/widgets/delete_account_action.dart';

class SettingsDataSource {
  static List<SettingsSection> getSettingsSections(
    BuildContext context,
    String currentUserId, {
    bool quietStatesOn = false,
    bool outsidePerspectiveOn = false,
    SettingsSection? chatFeel,
  }) {
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isAuthenticated = currentUserId.isNotEmpty;

    return [
      // A colour per setting, so each is easy to find again; related ones
      // share a family. Red is kept for safety and what can't be undone;
      // grey for app settings, support and legal.
      // Who you are.
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
              id: 'qr_code',
              title: loc.qrCodeItemTitle,
              subtitle: loc.qrCodeItemSubtitle,
              icon: Icons.qr_code_2_rounded,
              type: SettingsItemType.navigation,
              iconColor: Colors.purple,
              order: 2,
            ),
SettingsConfig(
              id: 'share_profile',
              title: loc.shareProfileItemTitle,
              subtitle: loc.shareProfileItemSubtitle,
              icon: Icons.share,
              url: 'https://yourapp.com/privacy',
              type: SettingsItemType.link,
              iconColor: Colors.blue,
              order: 3,
            ),
        ],
      ),
      // How chat feels: sounds, motion, phrasing (built by the screen,
      // which holds those switches); high up, since it's used most.
      if (chatFeel != null) chatFeel,
      if (isAuthenticated)
      SettingsSection(
        id: 'notifications_location',
        title: 'Notifications & location',
        items: [
SettingsConfig(
              id: 'notifications',
              title: loc.notificationsItemTitle,
              subtitle: loc.notificationsItemSubtitle,
              icon: Icons.notifications,
              type: SettingsItemType.navigation,
              routeName: '/notifications',
              iconColor: Colors.orange,
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
        ],
      ),
      if (isAuthenticated)
      SettingsSection(
        id: 'safety',
        title: 'Safety',
        items: [
SettingsConfig(
            id: 'safety_resources',
            title: 'Safety resources',
            subtitle: 'Open support contacts and quick exit tools',
            icon: Icons.shield_outlined,
            type: SettingsItemType.navigation,
            routeName: '/safety-resources',
            iconColor: Colors.red,
            order: 1,
          ),
SettingsConfig(
            id: 'safety_pin',
            title: 'Safety PIN',
            subtitle: 'Asked for after you use quick exit',
            icon: Icons.pin_outlined,
            type: SettingsItemType.navigation,
            routeName: '/settings/safety-pin',
            iconColor: Colors.deepOrange,
            order: 2,
          ),
SettingsConfig(
              id: 'blocked',
              title: loc.blockedItemTitle,
              subtitle: loc.blockedItemSubtitle,
              icon: Icons.block,
              type: SettingsItemType.navigation,
              routeName: '/blockedAccountsScreen',
              iconColor: Colors.red,
              order: 3,
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
              iconColor: Colors.pink,
              order: 4,
            ),
        ],
      ),
      if (isAuthenticated)
      SettingsSection(
        id: 'privacy',
        title: 'Privacy & your data',
        items: [
SettingsConfig(
              id: 'signed_in_devices',
              title: "Where you're signed in",
              subtitle: 'See the phones on your account',
              icon: Icons.devices_outlined,
              type: SettingsItemType.navigation,
              routeName: '/settings/signed-in-devices',
              iconColor: Colors.indigo,
              order: 1,
            ),
// Spec 3c (F1 (5)): a copy of what's theirs, at any time.
SettingsConfig(
              id: 'download_my_data',
              title: 'Download my data',
              subtitle: "A copy of what's yours",
              icon: Icons.download_outlined,
              type: SettingsItemType.navigation,
              routeName: '/settings/download-my-data',
              iconColor: Colors.blue,
              order: 2,
            ),
        ],
      ),
      if (isAuthenticated)
      SettingsSection(
        id: 'care',
        title: 'Care & wellbeing',
        items: [
if (quietStatesOn)
SettingsConfig(
            id: 'quiet_states',
            title: 'Quiet for a while',
            subtitle: 'When celebrations would feel wrong',
            icon: Icons.cloud_outlined,
            type: SettingsItemType.navigation,
            routeName: '/settings/quiet',
            iconColor: Colors.deepPurple.shade200,
            order: 1,
          ),
SettingsConfig(
            id: 'hidden_periods',
            title: 'Hide a period',
            subtitle: 'Dates that never come back as memories',
            icon: Icons.visibility_off_outlined,
            type: SettingsItemType.navigation,
            routeName: '/settings/hidden-periods',
            iconColor: Colors.blueGrey,
            order: 2,
          ),
if (outsidePerspectiveOn)
SettingsConfig(
            id: 'outside_perspective',
            title: 'A trained outside perspective',
            subtitle: 'What couples counselling is, and how to find it',
            icon: Icons.support_agent_outlined,
            type: SettingsItemType.navigation,
            routeName: '/support/outside-perspective',
            iconColor: Colors.purple,
            order: 3,
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
            order: 2,
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
            order: 4,
          ),
SettingsConfig(
            id: 'appInfoScreen',
            title: loc.appInfoItemTitle(AppConstants.appName),

            subtitle: loc.appInfoItemSubtitle,
            icon: Icons.memory,
            type: SettingsItemType.navigation,
            routeName: '/appInfoScreen',
            iconColor: Colors.grey,
            order: 5,
          ),
        ],
      ),
      SettingsSection(
        id: 'legal',
        title: loc.legalSectionTitle,
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
            order: 2,
          ),
        ],
      ),
      // Pausing or ending the shared space: its own place, apart from the
      // account actions.
      if (isAuthenticated)
      SettingsSection(
        id: 'relationship',
        title: 'Your relationship',
        items: [
// Spec 3a (F1 (3)): read-only for both, nothing new shared, no
// notification; either resumes or ends within 30 days.
SettingsConfig(
              id: 'pause_relationship',
              title: 'Pause our shared space',
              subtitle: 'Chat becomes read-only for both of you',
              icon: Icons.pause_circle_outline,
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
                    context.showErrorSnackbar('No active shared space to pause.');
                  }
                  return;
                }
                if (context.mounted) {
                  PauseRelationshipAction.confirmAndPause(
                    context,
                    relationshipId: relationshipId,
                  );
                }
              },
              iconColor: theme.colorScheme.error,
              order: 1,
            ),
SettingsConfig(
              id: 'endRelationship',
              title: 'End relationship',
              subtitle: 'Your chat stays readable for 30 days, then closes',
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
              order: 2,
            ),
        ],
      ),
      if (isAuthenticated)
      SettingsSection(
        id: 'danger',
        title: loc.accountActionsSectionTitle,
        showDivider: false,
        items: [
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
SettingsConfig(
              id: 'deactivate',
              title: loc.deactivateItemTitle,
              subtitle: loc.deactivateItemSubtitle,
              icon: Icons.person_off_outlined,
              type: SettingsItemType.action,
              onTap: () {},
              iconColor: Colors.blueGrey,
              order: 2,
            ),
// GDPR erasure (ATTUNE_MASTER_SPEC.md §10: "User can delete
// account and all data at any time"). Ordered last — below
// logout — so the irreversible action is the hardest of the
// three to hit by accident.
SettingsConfig(
              id: 'deleteAccount',
              title: 'Delete account',
              subtitle: 'Permanently delete your account and personal data',
              icon: Icons.delete_forever_outlined,
              type: SettingsItemType.destructive,
              onTap: () => DeleteAccountAction.confirmAndDelete(context),
              iconColor: theme.colorScheme.error,
              order: 3,
            ),
        ],
      ),
    ];
  }
}
