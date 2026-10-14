import 'package:attune/features/games/presentation/widgets/game_palette.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/sliding_scale/presentation/widgets/sliding_scale_track.dart';
import 'package:flutter/material.dart';

/// Rates one statement on the 1-10 scale (§8.4).
///
/// The slider is bounded to 1-10 with integer divisions, so the UI
/// cannot produce a value the server would reject — the write-time
/// constraint in submit_session_game_answer is the backstop, not the
/// primary control.
class SlidingScaleQuestionScreen extends StatefulWidget {
  const SlidingScaleQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  State<SlidingScaleQuestionScreen> createState() =>
      _SlidingScaleQuestionScreenState();
}

class _SlidingScaleQuestionScreenState
    extends State<SlidingScaleQuestionScreen> {
  double _value = 5;

  @override
  Widget build(BuildContext context) {
    final palette = GamePalette.of('sliding_scale');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // The spectrum, drawn. This game's whole subject is a gradient
          // and it shipped as a default slider on a default background;
          // its palette entry has been teal-into-blue all along, unused.
          //
          // The Slider stays as the INPUT: it is the accessible, tested,
          // platform-correct control, and its divisions are what keep the
          // answer inside the 1-10 the server accepts. What changes is
          // that the value is now shown rather than only held.
          SlidingScaleTrack(
            fraction: slidingScaleFraction(_value),
            lowColor: palette.start,
            highColor: palette.end,
          ),
          SliderTheme(
            // The track is drawn above; the slider is the hit target.
            // Transparent rather than removed, because replacing it with
            // a GestureDetector would mean reimplementing keyboard
            // traversal, screen-reader semantics and drag handling that
            // Slider already gets right.
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: palette.end,
              overlayColor: palette.end.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: _value,
              min: 1,
              max: 10,
              divisions: 9, // nine intervals across ten positions
              label: _value.round().toString(),
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(widget.question.scaleLow ?? '')),
              Flexible(child: Text(widget.question.scaleHigh ?? '')),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => widget.onSubmit(_value.round().toString()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
