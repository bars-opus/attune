import 'package:flutter/material.dart';

/// The capture button, with a circular progress ring drawn AROUND it that
/// fills over one segment's duration and resets at each split — a full
/// sweep is the signal that a segment just closed, which matters because
/// the user is looking at their subject rather than the button.
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

  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onPressStart(),
      onPointerUp: (_) => onPressEnd(),
      onPointerCancel: (_) => onPressEnd(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isRecording)
              SizedBox(
                width: _size,
                height: _size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isRecording ? 44 : 60,
              height: isRecording ? 44 : 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording ? Colors.redAccent : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
