import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/presentation/toolkit_overflow.dart';

/// Spec 8 (B3; plan review M8): the four tools under one attach entry.
enum HardMomentAction { pause, repair, apology, start }

Future<HardMomentAction?> showHardMomentSheet(BuildContext context) =>
    showModalBottomSheet<HardMomentAction>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const HardMomentSheet(),
    );

class HardMomentSheet extends StatelessWidget {
  const HardMomentSheet({super.key});

  static const _rows = [
    (
      HardMomentAction.pause,
      'Take a pause',
      'Step back, with a time to return',
      Icons.self_improvement_outlined,
    ),
    (
      HardMomentAction.repair,
      'Repair',
      'A short line to soften things',
      Icons.healing_outlined,
    ),
    (
      HardMomentAction.apology,
      'Help me apologise',
      'In your own words',
      Icons.edit_note_outlined,
    ),
    (
      HardMomentAction.start,
      'Start a conversation',
      'What happened, how it felt, what you need',
      Icons.forum_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ToolkitSheetTitle(
              title: 'In a hard moment',
              subtitle:
                  'Each one only fills your message. Nothing sends by itself.',
            ),
            Gap(Spacing.sm.h),
            for (final (action, title, subtitle, icon) in _rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(title),
                subtitle: Text(subtitle),
                onTap: () => Navigator.pop(context, action),
              ),
          ],
        ),
      ),
    );
  }
}
