import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/config/feature/notification_config.dart';
import 'package:attune/core/notifications/presentation/providers/notification_provider.dart';
import 'package:attune/core/notifications/presentation/providers/notification_settings_notifier.dart';
import 'package:attune/core/notifications/presentation/providers/notification_state.dart';
import 'package:attune/core/widgets/feedback/circular_loading_indicator.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(notificationSettingsProvider.notifier).loadSettings(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Settings',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(state, notifier),
    );
  }

  Widget _buildBody(
    NotificationSettingsState state,
    NotificationSettingsNotifier notifier,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularLoadingIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48.w,
              color: Theme.of(context).colorScheme.error,
            ),
            Gap(Spacing.md.h),
            Text(
              state.error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            ElevatedButton(
              onPressed: () => notifier.loadSettings(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // App-specific type toggles come from the config — no source edits needed
    // when porting to a new app.
    final config = ref.watch(notificationConfigProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        // ── Push Notifications (master switch) ────────────────────────────────
        _buildSectionHeader('Push Notifications'),
        _buildSwitchTile(
          title: 'Enable Push Notifications',
          subtitle: 'Receive push notifications on your device',
          value: state.pushEnabled,
          onChanged: notifier.setPushEnabled,
        ),
        _buildSwitchTile(
          title: 'Chat Message Previews',
          subtitle: 'Show message snippets on your lock screen and in push alerts',
          value: state.chatMessagePreviewEnabled,
          onChanged: notifier.setChatMessagePreviewEnabled,
          enabled: state.pushEnabled,
        ),

        // ── App-specific notification type toggles ────────────────────────────
        if (config.settingToggles.isNotEmpty) ...[
          _buildSectionHeader('Notification Types'),
          for (final toggle in config.settingToggles)
            _buildSwitchTile(
              title: toggle.label,
              subtitle: toggle.description ?? '',
              value: toggle.getValue(state),
              onChanged: (v) => toggle.setValue(notifier, v),
              enabled: state.pushEnabled,
            ),
        ],

        // ── Marketing ─────────────────────────────────────────────────────────
        _buildSectionHeader('Marketing'),
        _buildSwitchTile(
          title: 'Marketing Communications',
          subtitle: 'Receive special offers and promotions',
          value: state.marketingEnabled,
          onChanged: notifier.setMarketingEnabled,
          enabled: state.pushEnabled,
        ),

        // ── Email ─────────────────────────────────────────────────────────────
        _buildSectionHeader('Email Notifications'),
        _buildSwitchTile(
          title: 'Email Notifications',
          subtitle: 'Receive notifications via email',
          value: state.emailEnabled,
          onChanged: notifier.setEmailEnabled,
        ),

        // ── Reset ─────────────────────────────────────────────────────────────
        if (state.pushEnabled || state.emailEnabled)
          Padding(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: OutlinedButton(
              onPressed: state.isSaving ? null : notifier.resetToDefaults,
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.error,
                side: BorderSide(color: colorScheme.error),
              ),
              child: const Text('Reset to Defaults'),
            ),
          ),

        if (state.isSaving)
          Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: const Center(child: CircularLoadingIndicator()),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.lg.h,
        Spacing.lg.w,
        Spacing.sm.h,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool) onChanged,
    bool enabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: enabled
              ? colorScheme.onSurface
              : colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                color: enabled
                    ? colorScheme.onSurface.withValues(alpha: 0.6)
                    : colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
      value: value && enabled,
      onChanged: enabled ? onChanged : null,
      activeColor: colorScheme.primary,
    );
  }
}
