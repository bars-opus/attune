import 'dart:async';

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/conflict_toolkit/data/pause_timer_store.dart';
import 'package:attune/features/conflict_toolkit/data/toolkit_texts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Spec 8 (B3 (a); plan review M3): the sender's own card above the
/// composer while a pause runs, then a gentle return. Drawn only on the
/// sender's device; nothing about it reaches the partner.
class PauseTimerCard extends ConsumerStatefulWidget {
  const PauseTimerCard({
    super.key,
    required this.relationshipId,
    required this.onStartConversation,
  });

  final String relationshipId;
  final VoidCallback onStartConversation;

  /// A return prompt older than this is cleared without showing.
  static const staleAfter = Duration(hours: 12);

  @override
  ConsumerState<PauseTimerCard> createState() => _PauseTimerCardState();
}

class _PauseTimerCardState extends ConsumerState<PauseTimerCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  PauseTimerNotifier get _timer =>
      ref.read(pauseTimerProvider(widget.relationshipId).notifier);

  @override
  Widget build(BuildContext context) {
    final end = ref.watch(pauseTimerProvider(widget.relationshipId));
    if (end == null) return const SizedBox.shrink();
    final now = ref.watch(pauseClockProvider)();
    final left = end.difference(now);
    if (-left > PauseTimerCard.staleAfter) {
      scheduleMicrotask(_timer.clear);
      return const SizedBox.shrink();
    }
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final running = left > Duration.zero;
    final minutes = (left.inSeconds / 60).ceil();

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: Spacing.md.w,
        vertical: Spacing.xs.h,
      ),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              running ? 'Back in about $minutes min' : kReturnPrompt,
              style: text.titleSmall,
            ),
            Gap(Spacing.xs.h),
            if (running)
              Text(
                kSelfSoothingCopy,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            Gap(Spacing.xs.h),
            Wrap(
              spacing: Spacing.sm.w,
              children: [
                if (!running)
                  FilledButton.tonal(
                    onPressed: () {
                      _timer.clear();
                      widget.onStartConversation();
                    },
                    child: const Text('Start a conversation'),
                  ),
                TextButton(
                  onPressed: _timer.clear,
                  child: Text(running ? 'End now' : 'Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
