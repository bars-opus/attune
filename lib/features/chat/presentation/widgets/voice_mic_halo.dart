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
  });

  /// 0..1 of the current input level.
  final double amplitude;
  final bool isRecording;
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
        Container(
          key: const ValueKey('voice-mic-disc'),
          width: _disc,
          height: _disc,
          decoration: BoxDecoration(shape: BoxShape.circle, color: primary),
          child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white, size: 24),
            child: Center(child: child),
          ),
        ),
      ],
    );
  }
}
