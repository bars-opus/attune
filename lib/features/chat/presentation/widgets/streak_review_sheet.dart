import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter/material.dart';

/// The step between recording and sending: send, or cancel.
///
/// Deliberately just those two. A streak is a fast, casual thing — the
/// value is in sending it, not composing it — so there is no caption
/// field, and whether replays are allowed is a persistent choice in chat
/// settings rather than a decision to make on every send.
///
/// It exists at all because a streak should not fly away the instant a
/// finger lifts: a mis-hold would otherwise be unrecallable.
class StreakReviewSheet extends StatelessWidget {
  const StreakReviewSheet({
    super.key,
    required this.segments,
    required this.onSend,
    required this.onDiscard,
  });

  final List<StreakSegment> segments;
  final VoidCallback onSend;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final seconds = segments
        .fold<Duration>(Duration.zero, (sum, s) => sum + s.duration)
        .inSeconds;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            // Just the length. A streak is always one clip now, so a count
            // said nothing — and the duration is the only thing worth
            // knowing before deciding whether to send.
            '${seconds}s',
            style: textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onSend,
                  child: const Text('Send'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
