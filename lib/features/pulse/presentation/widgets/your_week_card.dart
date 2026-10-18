// lib/features/pulse/presentation/widgets/your_week_card.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/data/models/your_week.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The self-facing half of Pulse (Spec 1a; SOUL §9): my private Emotional
/// safety and my own check-in answers. Rendered from auth.uid()-only data;
/// the partner has their own.
class YourWeekCard extends ConsumerWidget {
  const YourWeekCard({super.key});

  static const _rows = <(String, int? Function(WeeklyCheckinAnswers))>[
    ('Communication', _communication),
    ('Connection', _connection),
    ('Conflict health', _conflictHealth),
    ('Alignment', _alignment),
    ('Emotional safety answer', _safety),
  ];

  static int? _communication(WeeklyCheckinAnswers a) => a.communication;
  static int? _connection(WeeklyCheckinAnswers a) => a.connection;
  static int? _conflictHealth(WeeklyCheckinAnswers a) =>
      a.conflictHealthNA ? null : a.conflictHealth;
  static int? _alignment(WeeklyCheckinAnswers a) => a.alignment;
  static int? _safety(WeeklyCheckinAnswers a) => a.safety;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final weekAsync = ref.watch(yourWeekProvider);

    return weekAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (week) {
        final checkin = week.checkin;
        return CardInkWell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your week',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Gap(Spacing.xs.h),
              Text(
                'Only you can see this.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Gap(Spacing.md.h),
              if (checkin == null)
                Text('No check-in this week yet.', style: textTheme.bodyMedium)
              else ...[
                Row(
                  children: [
                    Text('Emotional safety', style: textTheme.bodyMedium),
                    const Spacer(),
                    Text(
                      week.emotionalSafety?.toString() ?? '—',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Gap(Spacing.xs.h),
                Text(
                  'From your check-in and the moments you both logged.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Gap(Spacing.md.h),
                Text(
                  'Your answers',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Gap(Spacing.xs.h),
                for (final (label, read) in _rows)
                  Padding(
                    padding: EdgeInsets.only(bottom: Spacing.xs.h),
                    child: Row(
                      children: [
                        Text(label, style: textTheme.bodyMedium),
                        const Spacer(),
                        Text(switch (read(checkin)) {
                          null => 'Not this week',
                          final v => '$v/10',
                        }, style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
