import 'package:attune/core/utils/exports/export_screens.dart';

/// Spec 7 (research 06 B9 (b); plan ruling P7): say what kind of support you
/// want. Each chip puts a fixed, editable line in the composer; nothing is
/// sent until the person sends it.
const supportDrafts = <String, String>{
  'I need to vent': 'I need to vent. Can you just listen for a bit?',
  'Help me decide': 'Can you help me decide something?',
  'Just sit with me': 'Can you just sit with me for a bit?',
};

Future<String?> showSupportChipsSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      builder:
          (context) => SupportChipsSheet(
            onPick: (draft) => Navigator.pop(context, draft),
          ),
    );

class SupportChipsSheet extends StatelessWidget {
  const SupportChipsSheet({super.key, required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What would help?', style: text.titleMedium),
            Gap(Spacing.md.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.sm.h,
              children: [
                for (final e in supportDrafts.entries)
                  ActionChip(
                    label: Text(e.key),
                    onPressed: () => onPick(e.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
