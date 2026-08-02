// lib/features/reflection_journal/presentation/widgets/journal_entry_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:intl/intl.dart';

class JournalEntryCard extends StatelessWidget {
  const JournalEntryCard({super.key, required this.entry, required this.onTap});

  final JournalEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final preview = entry.content.length > 120
        ? '${entry.content.substring(0, 120)}…'
        : entry.content;

    return CardInkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat.yMMMd().format(entry.createdAt),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              if (entry.tone != null) ...[
                Gap(Spacing.sm.w),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.sm.w,
                    vertical: 2.h,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.sm.r,
                    ),
                  ),
                  child: Text(
                    entry.tone!,
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Gap(Spacing.sm.h),
          Text(
            preview,
            style: textTheme.bodyMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
