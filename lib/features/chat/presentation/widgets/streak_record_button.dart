import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The streak capture control.
///
/// Three states:
///
///   IDLE — a hollow ring on the dark camera surface. An outline rather
///     than a disc, so the viewfinder stays readable behind it and the
///     button reads as "ready" rather than "active".
///
///   RECORDING — a filled disc in the app's primary colour with a
///     progress arc ringing it, separated by a clear gap so the two read
///     as distinct shapes rather than one thick stroke.
///
///   BUSY (preparing or sending) — the same ring, sweeping
///     indeterminately. Neither camera init nor an upload has measurable
///     progress, and the control itself is the honest place to show that
///     something is happening; a spinner in the middle of a black screen
///     says nothing more and reads as a failed launch.
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
    this.isSending = false,
    this.isPreparing = false,
  });

  /// 0..1 through the CURRENT segment, not the whole recording.
  final double progress;
  final bool isRecording;

  /// Uploading. The button becomes the loading indicator and stops
  /// accepting presses — starting a second recording mid-upload would
  /// queue a send behind one already in flight.
  final bool isSending;

  /// The camera is still initialising. Same treatment as sending: the
  /// ring sweeps and the button refuses presses, so the launch reads as
  /// "warming up" rather than as a broken black screen.
  final bool isPreparing;

  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  /// The touch target, sized for a thumb regardless of what is drawn.
  static const double _target = 112;

  static const double _idleDiameter = 72;
  static const double _discDiameter = 64;

  /// Gap between the disc and the arc ringing it.
  static const double _gap = Spacing.lg;

  static const double _arcStroke = 6;
  static const double _ringStroke = 5;

  double get _arcDiameter => _discDiameter + _gap * 2;

  bool get _isBusy => isSending || isPreparing;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Listener(
      onPointerDown: (_) {
        if (_isBusy) return;
        // Light rather than medium: this fires the instant a finger lands
        // on the button, many times a session. A heavier tap would become
        // wearing very quickly.
        HapticFeedback.lightImpact();
        onPressStart();
      },
      onPointerUp: (_) {
        if (_isBusy) return;
        onPressEnd();
      },
      onPointerCancel: (_) {
        if (_isBusy) return;
        onPressEnd();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _target,
        height: _target,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isBusy)
              SizedBox(
                key: const ValueKey('streak-record-sending'),
                width: _idleDiameter,
                height: _idleDiameter,
                child: CircularProgressIndicator(
                  // Indeterminate: an upload's duration is unknown, and a
                  // fake determinate bar would be a lie.
                  strokeWidth: _ringStroke,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(primary),
                ),
              )
            else if (isRecording) ...[
              AnimatedContainer(
                key: const ValueKey('streak-record-fill'),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _discDiameter,
                height: _discDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary,
                ),
              ),
              SizedBox(
                key: const ValueKey('streak-record-arc'),
                width: _arcDiameter,
                height: _arcDiameter,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: _arcStroke,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(primary),
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
                    // Recessive until pressed: a white ring on a dark
                    // viewfinder pulls the eye off the subject.
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
