// lib/features/timeline/presentation/widgets/moment_card.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

class MomentCard extends ConsumerStatefulWidget {
  final TimelineEventModel event;
  final String currentUserId;
  final DateTime currentMonth;

  const MomentCard({
    super.key,
    required this.event,
    required this.currentUserId,
    required this.currentMonth,
  });

  @override
  ConsumerState<MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends ConsumerState<MomentCard> {
  bool _isDeleting = false;

  bool get _isOwnEvent => widget.event.loggedBy == widget.currentUserId;

  void _editMoment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LogMomentDetailsScreen(
              eventType: widget.event.eventType,
              editEventId: widget.event.id,
              initialData: {
                'title': widget.event.title,
                'note': widget.event.note,
                'occurred_at': widget.event.occurredAt,
                'mood_score': widget.event.moodScore,
              },
            ),
      ),
    ).then((refreshNeeded) {
      if (refreshNeeded == true && mounted) {
        ref.invalidate(timelineEventsProvider(widget.currentMonth));
      }
    });
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete this moment?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() => _isDeleting = true);

                try {
                  await ref.read(
                    deleteTimelineEventProvider(widget.event.id).future,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Moment deleted')),
                    );
                    ref.invalidate(timelineEventsProvider(widget.currentMonth));
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete: $e')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isDeleting = false);
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final eventColor = widget.event.eventTypeColor(colorScheme);

    final formattedDate = DateFormat(
      'MMM d, yyyy',
    ).format(widget.event.occurredAt);
    final loggedByName =
        _isOwnEvent ? 'You' : 'Partner'; // In real app, fetch partner's name

    return Container(
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(color: colorScheme.outline.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: dot + type + date + menu
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: eventColor,
                ),
              ),
              Gap(Spacing.sm.w),
              Text(
                widget.event.eventTypeDisplay,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: eventColor,
                ),
              ),
              const Spacer(),
              Text(
                formattedDate,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              if (_isOwnEvent && !_isDeleting)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editMoment();
                    } else if (value == 'delete') {
                      _showDeleteConfirmation();
                    }
                  },
                  itemBuilder:
                      (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                ),
              if (_isDeleting)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          Gap(Spacing.sm.h),
          // Title
          Text(
            widget.event.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          // Note (if exists)
          if (widget.event.note != null && widget.event.note!.isNotEmpty) ...[
            Gap(Spacing.sm.h),
            Text(widget.event.note!, style: textTheme.bodyMedium),
          ],
          // Mood bar (if exists)
          if (widget.event.moodScore != null) ...[
            Gap(Spacing.md.h),
            Row(
              children: [
                Text('Mood:', style: textTheme.bodySmall),
                Gap(Spacing.sm.w),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.sm.r,
                    ),
                    child: LinearProgressIndicator(
                      value: widget.event.moodScore! / 10,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: eventColor,
                    ),
                  ),
                ),
                Gap(Spacing.sm.w),
                Text(
                  '${widget.event.moodScore}/10',
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          Gap(Spacing.sm.h),
          // Logged by
          Text(
            'Logged by: $loggedByName',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
