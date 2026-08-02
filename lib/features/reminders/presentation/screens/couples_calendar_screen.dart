// lib/features/reminders/presentation/screens/couples_calendar_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/reminders/data/models/reminder_model.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CouplesCalendarScreen extends ConsumerWidget {
  const CouplesCalendarScreen({super.key});

  DateTime _nextOccurrence(ReminderModel reminder) {
    if (!reminder.isRecurring) return reminder.remindAt;
    final now = DateTime.now();
    var next = DateTime(now.year, reminder.remindAt.month, reminder.remindAt.day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year + 1, reminder.remindAt.month, reminder.remindAt.day);
    }
    return next;
  }

  String _countdownLabel(DateTime occurrence) {
    final today = DateTime.now();
    final days = DateTime(occurrence.year, occurrence.month, occurrence.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersListProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Calendar',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () => context.pushNamed('familyMembers'),
          ),
        ],
      ),
      body: remindersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle: 'We couldn\'t load your calendar right now. Please try again in a moment.',
          ),
        ),
        data: (reminders) {
          if (reminders.isEmpty) {
            return Center(
              child: EmptyStateWidget(
                title: 'No events yet',
                subtitle: 'Add an anniversary, birthday, or any date you want to remember together.',
              ),
            );
          }
          final sorted = [...reminders]
            ..sort((a, b) => _nextOccurrence(a).compareTo(_nextOccurrence(b)));
          return ListView.separated(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => Gap(Spacing.sm.h),
            itemBuilder: (context, index) {
              final reminder = sorted[index];
              final occurrence = _nextOccurrence(reminder);
              return Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Row(
                  children: [
                    Icon(reminder.isRecurring ? Icons.repeat : Icons.event_outlined),
                    Gap(Spacing.sm.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(reminder.title, style: textTheme.titleSmall),
                          Text(_countdownLabel(occurrence), style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.pushNamed('addEditReminder'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
