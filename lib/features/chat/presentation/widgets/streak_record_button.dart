import 'package:flutter/material.dart';

/// The streak capture control.
///
/// Two states, matching the reference:
///
///   IDLE — a hollow ring on the dark camera surface. An outline rather
///     than a disc, so the viewfinder stays readable behind it and the
///     button reads as "ready" rather than "active".
///
///   RECORDING — a large filled disc in the app's primary colour, with a
///     thick progress arc sweeping around it over the segment's duration.
///     A full sweep is the signal that a segment just closed, which
///     matters because the user is watching their subject, not the button.
///
/// The reference uses Snapchat's yellow; this uses `colorScheme.primary`
/// so it stays on-brand and correct in both themes.
///
/// A raw Listener rather than GestureDetector's pan callbacks: pan does
/// not report an end for a press with no movement, so a quick tap would
/// start a recording that never stops (the bug fixed in 511f4665).
class StreakRecordButton extends StatelessWidget {
  const StreakRecordButton({
    super.key,
    required this.progress,
    required this.isRecording,
    required this.onPressStart,
    required this.onPressEnd,
  });

  /// 0..1 through the CURRENT segment, not the whole recording.
  final double progress;
  final bool isRecording;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  /// The touch target, sized for a thumb regardless of what is drawn.
  static const double _target = 96;

  /// The idle ring, and the recording disc it grows into.
  static const double _idleDiameter = 72;
  static const double _activeDiameter = 88;

  /// Thick enough to read at a glance from the corner of the eye.
  static const double _arcStroke = 9;
  static const double _ringStroke = 5;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Listener(
      onPointerDown: (_) => onPressStart(),
      onPointerUp: (_) => onPressEnd(),
      onPointerCancel: (_) => onPressEnd(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _target,
        height: _target,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording) ...[
              // The disc first, the arc over it: the arc's stroke sits on
              // the disc's edge in the reference, not outside it.
              AnimatedContainer(
                key: const ValueKey('streak-record-fill'),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _activeDiameter,
                height: _activeDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary,
                ),
              ),
              SizedBox(
                width: _activeDiameter,
                height: _activeDiameter,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: _arcStroke,
                  // Transparent track: the unfilled part of the sweep
                  // should show the disc, not a competing ring.
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(
                    // A darker cast of the same colour, so the arc reads
                    // against the disc without introducing a second hue.
                    Color.alphaBlend(Colors.black26, primary),
                  ),
                ),
              ),
            ] else
              Container(
                key: const ValueKey('streak-record-ring'),
                width: _idleDiameter,
                height: _idleDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    // Grey rather than white: the reference ring is
                    // recessive until it is pressed, and a white ring on a
                    // dark viewfinder pulls the eye off the subject.
                    color: Colors.white70,
                    width: _ringStroke,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
