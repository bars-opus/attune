import 'package:flutter/material.dart';

/// The mic button while recording: a filled primary disc with a soft halo
/// that breathes with the speaker's voice.
///
/// The halo is the amplitude made visible. A fixed ring would say nothing
/// the disc does not already say, where a reactive one confirms the
/// microphone is actually hearing something — the single most useful
/// thing to know mid-recording.
///
/// Idle renders the child alone, so the composer looks untouched until a
/// recording actually starts.
class VoiceMicHalo extends StatelessWidget {
  const VoiceMicHalo({
    super.key,
    required this.amplitude,
    required this.isRecording,
    required this.child,
    this.progress = 0,
    this.isLocked = false,
  });

  /// 0..1 of the current input level.
  final double amplitude;
  final bool isRecording;

  /// 0..1 through the recorder's own maximum. Voice notes cap at five
  /// minutes, and without this the user only learns they were close when
  /// the recorder cuts them off.
  final double progress;

  /// Once locked the finger has left the button, so the halo and the
  /// ring are noise: the bar's own controls own that state. The disc
  /// stays so the composer keeps its shape.
  final bool isLocked;

  final Widget child;

  static const double _disc = 48;
  static const double _haloMin = 56;
  static const double _haloMax = 92;

  @override
  Widget build(BuildContext context) {
    if (!isRecording) return child;

    final primary = Theme.of(context).colorScheme.primary;
    final level = amplitude.clamp(0.0, 1.0);
    final halo = _haloMin + (_haloMax - _haloMin) * level;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Behind the disc and translucent, so a loud moment reads as the
        // button swelling rather than as a second element appearing.
        if (!isLocked)
          AnimatedContainer(
            key: const ValueKey('voice-mic-halo'),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: halo,
            height: halo,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.22),
            ),
          ),
        // Between the halo and the disc, so the sweep reads as the
        // button's own edge rather than a separate ring floating near it.
        if (!isLocked)
          SizedBox(
            width: _disc + 8,
            height: _disc + 8,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 3,
              backgroundColor: primary.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(primary),
            ),
          ),
        Container(
          key: const ValueKey('voice-mic-disc'),
          width: _disc,
          height: _disc,
          decoration: BoxDecoration(shape: BoxShape.circle, color: primary),
          child: IconTheme.merge(
            // onPrimary, not white: in dark mode the primary disc is
            // light and a white glyph vanishes into it.
            data: IconThemeData(
              color: Theme.of(context).colorScheme.onPrimary,
              size: 24,
            ),
            child: Center(child: child),
          ),
        ),
      ],
    );
  }
}
