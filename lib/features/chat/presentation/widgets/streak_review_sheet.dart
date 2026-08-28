import 'package:attune/features/chat/domain/services/streak_recording_session.dart';
import 'package:flutter/material.dart';

/// The step between recording and sending: add a caption, choose whether
/// replays are allowed, send or discard.
///
/// The clips are already captured by the time this opens — this exists so
/// the user can say something about them or back out, not to decide
/// whether the recording happened.
class StreakReviewSheet extends StatefulWidget {
  const StreakReviewSheet({
    super.key,
    required this.segments,
    required this.onSend,
    required this.onDiscard,
  });

  final List<StreakSegment> segments;

  /// [allowReplays] grants the recipient up to 3 total views instead of 1.
  final void Function(String caption, bool allowReplays) onSend;
  final VoidCallback onDiscard;

  @override
  State<StreakReviewSheet> createState() => _StreakReviewSheetState();
}

class _StreakReviewSheetState extends State<StreakReviewSheet> {
  final _caption = TextEditingController();

  /// Off by default: strict view-once is the default and the sender opts
  /// OUT of it, never the reverse.
  bool _allowReplays = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.segments.length;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            count == 1 ? '1 clip' : '$count clips',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            maxLength: 200,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Add a message',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allowReplays,
            onChanged: (v) => setState(() => _allowReplays = v),
            title: const Text('Allow replays'),
            subtitle: const Text('They can watch up to 3 times'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: widget.onDiscard,
                child: const Text('Discard'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () =>
                    widget.onSend(_caption.text.trim(), _allowReplays),
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
