import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:attune/features/conflict_toolkit/presentation/toolkit_overflow.dart';

/// Spec 8 (B3 (b)): six fixed phrases; the chosen one goes into the
/// composer to edit or send. No label, no record.
Future<String?> showRepairTray(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const RepairTray(),
    );

class RepairTray extends StatelessWidget {
  const RepairTray({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ToolkitSheetTitle(title: 'Repair'),
              Gap(Spacing.sm.h),
              // Full-width rows, so each phrase wraps at large text sizes
              // rather than fading out (final review m-6).
              for (final phrase in kRepairPhrases)
                Padding(
                  padding: EdgeInsets.only(top: Spacing.sm.h),
                  child: ListTile(
                    title: Text(phrase),
                    tileColor: scheme.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.md.r,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, phrase),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
