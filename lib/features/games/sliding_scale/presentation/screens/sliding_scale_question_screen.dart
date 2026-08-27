import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
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
          Slider(
            value: _value,
            min: 1,
            max: 10,
            divisions: 9, // nine intervals across ten positions
            label: _value.round().toString(),
            onChanged: (v) => setState(() => _value = v),
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
