// lib/features/settings/data/settings_data.dart

import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:attune/features/settings/models/settings_config.dart';

class ProfileMoreData {
  static List<SettingsSection> getSettingsSections(BuildContext context) {
    // Access localization for language prefence
    final loc = AppLocalizations.of(context)!;

    final theme = Theme.of(context);
    return [
      SettingsSection(
        id: 'app_actions',
        title: 'App Action',
        items: [
          SettingsConfig(
            id: 'block',
            title: loc.actionsBlock,
            subtitle: '',
            icon: Icons.block,
            type: SettingsItemType.destructive,
            routeName: '/block',
            iconColor: Colors.red,
            order: 1,
          ),
          SettingsConfig(
            id: 'report',
            title: loc.actionsReport,
            subtitle: '',
            icon: Icons.flag_outlined,
            type: SettingsItemType.destructive,
            url: 'https://yourapp.com/privacy',
            onTap: () {},
            iconColor: Colors.red,
            order: 3,
          ),
        ],
      ),

      SettingsSection(
        id: 'profile_actions',
        title: 'Profile Action',
        items: [
          SettingsConfig(
            id: 'send',
            title: loc.actionsSend,
            subtitle: '',
            icon: Icons.send_outlined,
            type: SettingsItemType.navigation,
            onTap: () {},
            iconColor: theme.colorScheme.onBackground.withOpacity(.6),
            order: 1,
          ),

          SettingsConfig(
            id: 'share',
            title: loc.actionsShare,
            subtitle: '',
            icon: Icons.share,
            type: SettingsItemType.link,
            url: 'https://yourapp.com/privacy',
            routeName: '/share',
            iconColor: theme.colorScheme.onBackground.withOpacity(.6),
            order: 2,
          ),
          SettingsConfig(
            id: 'copy',
            title: loc.actionsCopy,
            subtitle: '',
            icon: Icons.copy,
            type: SettingsItemType.link,
            url: 'https://yourapp.com/privacy',
            routeName: '/copy',
            iconColor: theme.colorScheme.onBackground.withOpacity(.6),
            order: 3,
          ),
        ],
      ),

      SettingsSection(
        id: 'app_actions',
        title: 'App Action',
        items: [
          SettingsConfig(
            id: 'feedback',
            title: loc.feedbackItemTitle,
            subtitle:
                'Share your thoughts with the ${AppConstants.appName} team',
            icon: Icons.feedback_outlined,
            type: SettingsItemType.navigation,
            onTap: () {},
            iconColor: theme.colorScheme.primary,
            order: 2,
          ),
        ],
      ),
    ];
  }
}
