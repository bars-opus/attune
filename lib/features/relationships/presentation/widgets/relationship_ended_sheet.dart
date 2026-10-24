import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the other partner sees, once, on their next open after the ending
/// (Spec 3a; research 06 §3 F1 (2); 05 D.3 #3): a sentence a friend would
/// say. No reason, no reply. Shown only while the chat is still readable
/// and only when the partner ended it (never for the system's 30-day pause
/// expiry or a new relationship).
class RelationshipEndedSheet extends StatelessWidget {
  const RelationshipEndedSheet({super.key, required this.lifecycle});

  final RelationshipLifecycle lifecycle;

  static String seenKey(String id) => 'relationship_ended_seen:$id';

  static Future<void> maybeShow(
    BuildContext context,
    RelationshipLifecycle l,
  ) async {
    if (l.status != LifecycleStatus.ended ||
        !l.endedByPartner ||
        !l.chatReadable ||
        l.sealedByMe) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(seenKey(l.relationshipId)) ?? false) return;
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RelationshipEndedSheet(lifecycle: l),
    );
    // Seen only if the person actually had it: a button, or a dismiss while
    // the app is in front. An unmount (the PIN lock replacing the app, or
    // quick exit) is not seeing it (final review IMP-2).
    final seen =
        choice != null ||
        (context.mounted &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
    if (!seen) return;
    await prefs.setBool(seenKey(l.relationshipId), true);
    if (choice != null && choice != _close) router.push(choice);
  }

  static const _close = 'close';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = lifecycle.partnerFirstName ?? 'Your partner';
    final until =
        lifecycle.windowEndsAt == null
            ? ''
            : MyDateFormat.toDate(lifecycle.windowEndsAt!.toLocal());
    // The caller pushes the route once the sheet is gone (final review MIN-7).
    void go(String route) => Navigator.of(context).pop(route);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Spacing.lg.w,
          0,
          Spacing.lg.w,
          Spacing.lg.h,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$name has ended your shared space.', style: text.titleLarge),
            Gap(Spacing.sm.h),
            Text(
              'For 30 days you can read what you shared. After $until it '
              'closes, and 12 months later it is deleted.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap(Spacing.lg.h),
            FilledButton(
              onPressed:
                  () => go(
                    '${RouteNames.chatChannel}?relationshipId='
                    '${lifecycle.relationshipId}',
                  ),
              child: const Text('Read our chat'),
            ),
            Gap(Spacing.sm.h),
            OutlinedButton(
              onPressed: () => go(RouteNames.healingJourney),
              child: const Text('Healing from a breakup?'),
            ),
            Gap(Spacing.sm.h),
            OutlinedButton(
              onPressed: () => go(RouteNames.safetyResources),
              child: const Text('Support resources'),
            ),
            Gap(Spacing.xs.h),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_close),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
