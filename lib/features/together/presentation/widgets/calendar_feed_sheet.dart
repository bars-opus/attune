import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The link, right after it's made (it can't be shown again: only its hash
/// is kept). Copy for Google; open for Apple Calendar.
Future<void> showCalendarFeedLinkSheet(
  BuildContext context,
  ({String https, String webcal}) links,
) => BottomSheetUtils.showDocumentationBottomSheet<void>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.neutral,
  widget: _CalendarFeedLinkSheet(links: links),
);

class _CalendarFeedLinkSheet extends StatelessWidget {
  const _CalendarFeedLinkSheet({required this.links});
  final ({String https, String webcal}) links;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        children: [
          const BottomSheetHeader(title: 'Your calendar link'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: SelectableText(
              links.https,
              maxLines: 3,
              style: text.bodySmall,
            ),
          ),
          Gap(Spacing.sm),
          InfoRowWidget(
            title: 'Copy link',
            subtitle: 'Google Calendar: Other calendars → From URL',
            icon: Icons.copy_rounded,
            showAvatar: false,
            showDivider: false,
            disableTrailing: true,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: links.https));
              if (context.mounted) context.showSuccessSnackbar('Link copied.');
            },
          ),
          // Only Apple Calendar answers webcal:// (Android has no handler).
          if (defaultTargetPlatform == TargetPlatform.iOS) ...[
            AppDivider(),
            InfoRowWidget(
              title: 'Open in Calendar',
              subtitle: 'Apple Calendar subscribes straight away',
              icon: Icons.event_available_rounded,
              showAvatar: false,
              showDivider: false,
              disableTrailing: true,
              onTap: () async {
                var ok = false;
                try {
                  ok = await launchUrl(Uri.parse(links.webcal));
                } catch (_) {}
                if (!ok && context.mounted) {
                  context.showErrorSnackbar('No calendar app could open it.');
                }
              },
            ),
          ],
          Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: SemanticContainerWidget(
              title: 'Keep this link to yourself',
              content:
                  'Anyone with this link can see your Together calendar. It is '
                  'shown only this once, so add it to your calendar now. You '
                  'can turn it off or get a new link in Together settings.',
              icon: Icons.warning_amber_rounded,
              backgroundColor: colorScheme.warning.withValues(alpha: 0.1),
              borderColor: colorScheme.warning,
              iconColor: colorScheme.warning,
              textTheme: text,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Spacing.md.w),
            child: Text(
              'Google refreshes subscribed calendars every 12–24 hours; Apple '
              'lets you choose how often.',
              style: text.bodySmall,
            ),
          ),
          Gap(Spacing.xl),
        ],
      ),
    );
  }
}
