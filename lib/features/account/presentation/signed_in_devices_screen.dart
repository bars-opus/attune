import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/account/data/account_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings → Where you're signed in (Spec 2; research 06 §3 F7 (1), (2)).
class SignedInDevicesScreen extends ConsumerWidget {
  const SignedInDevicesScreen({super.key});

  static IconData _icon(String? platform) => switch (platform) {
    'ios' => Icons.phone_iphone,
    'android' => Icons.phone_android,
    _ => Icons.devices,
  };

  void _confirmSignOutOthers(BuildContext context, WidgetRef ref) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 400.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.warning,
        title: 'Sign out all other devices?',
        message:
            'Every other phone signed in to your account will be signed out. '
            'It can take up to an hour for another phone to notice.',
        confirmText: 'Sign out others',
        onConfirm: () async {
          try {
            await ref
                .read(accountSessionsRepositoryProvider)
                .signOutOtherDevices();
            ref.invalidate(signedInDevicesProvider);
            if (context.mounted) {
              context.showSuccessSnackbar('Other devices are signed out.');
            }
          } catch (_) {
            if (context.mounted) {
              context.showErrorSnackbar(
                "Couldn't sign out other devices. Try again.",
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final devices = ref.watch(signedInDevicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Where you're signed in")),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => const EmptyStateWidget(
              icon: Icons.devices,
              title: "Couldn't load your devices",
              subtitle: 'Try again in a moment.',
            ),
        data:
            (list) => ListView(
              padding: EdgeInsets.all(Spacing.lg.w),
              children: [
                Text(
                  'Phones you no longer use stay here until you sign them out.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Gap(Spacing.md.h),
                for (final d in list)
                  InfoRowWidget(
                    title:
                        '${d.label ?? 'Unnamed device'}'
                        '${d.isCurrent ? ' · This phone' : ''}',
                    subtitle: MyDateFormat.join([
                      'Signed in ${MyDateFormat.toDate(d.signedInAt.toLocal())}',
                      'Last active ${MyDateFormat.toDate(d.lastActiveAt.toLocal())}',
                    ]),
                    icon: _icon(d.platform),
                    showAvatar: false,
                    showTrailingArrow: false,
                  ),
                Gap(Spacing.lg.h),
                if (list.length <= 1)
                  Text('Only this phone is signed in.', style: text.bodyMedium)
                else
                  AppButton(
                    label: 'Sign out all other devices',
                    width: double.infinity,
                    onPressed: () => _confirmSignOutOthers(context, ref),
                  ),
              ],
            ),
      ),
    );
  }
}
