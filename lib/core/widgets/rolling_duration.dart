import 'package:flutter/material.dart';

import 'animated_rolling_counter.dart';

/// A duration whose digits roll rather than cut when they change.
///
/// Reads as plain seconds below a minute and m:ss above it — a single
/// rolling seconds counter reaches "300" at the recorder's five-minute
/// ceiling, which reads as a raw number rather than a duration. Each
/// segment is its own counter so both keep the rolling animation.
///
/// Universal: knows nothing about voice messages. Used by the recording
/// scrim and the playback bubble, so a recording and its playback show
/// their time the same way.
class RollingDuration extends StatelessWidget {
  const RollingDuration({
    super.key,
    required this.value,
    this.style,
    this.keyPrefix = 'rolling-duration',
  });

  final Duration value;
  final TextStyle? style;

  /// Distinguishes the counters when several are on screen at once.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;

    if (minutes == 0) {
      return AnimatedRollingCounter(
        key: ValueKey('$keyPrefix-seconds'),
        count: value.inSeconds,
        style: style,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedRollingCounter(
          key: ValueKey('$keyPrefix-minutes'),
          count: minutes,
          style: style,
        ),
        Text(':', style: style),
        // Zero-padded: "1:5" reads as one-and-a-half minutes to as many
        // people as read it as one minute five.
        if (seconds < 10) Text('0', style: style),
        AnimatedRollingCounter(
          key: ValueKey('$keyPrefix-seconds'),
          count: seconds,
          style: style,
        ),
      ],
    );
  }
}
