import 'package:flutter/material.dart';

/// Replaces ChatTextField's text input area while a voice message is being
/// recorded — shows a live waveform (driven by [amplitude], a 0.0-1.0
/// normalized current level) and elapsed duration. Purely presentational;
/// ChatTextField owns the recording lifecycle and feeds this widget its
/// current state via rebuilds.
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    super.key,
    required this.elapsed,
    required this.amplitude,
    required this.isCancelling,
  });

  final Duration elapsed;

  /// Current normalized amplitude (0.0-1.0), driving the live bar height —
  /// NOT the full recorded waveform (that's only available after stop()).
  final double amplitude;

  /// True once the press has been dragged past the slide-to-cancel
  /// threshold — the bar re-colors to signal "release here to cancel."
  final bool isCancelling;

  String _formatElapsed(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final color = isCancelling
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Icon(Icons.fiber_manual_record, color: color, size: 12),
        const SizedBox(width: 8),
        Text(_formatElapsed(elapsed)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: amplitude.clamp(0.0, 1.0),
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
              minHeight: 24,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isCancelling ? 'Release to cancel' : 'Slide up to cancel',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
