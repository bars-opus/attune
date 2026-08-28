import 'package:attune/features/games/love_map/domain/love_map_selection.dart';
import 'package:flutter/material.dart';

/// One Love Map prompt.
///
/// Every seeded question is written in the third person about the subject
/// ("What are they most afraid of losing?"). That is right for the guesser
/// and wrong for the subject, who would otherwise be answering about their
/// partner — and that answer is stored as the truth about themselves, which
/// would corrupt the round. [isSubject] re-frames the screen so the subject
/// knows they are answering about themselves.
class LoveMapQuestionScreen extends StatefulWidget {
  const LoveMapQuestionScreen({
    super.key,
    required this.question,
    required this.isSubject,
    required this.onSubmit,
  });

  final LoveMapQuestion question;
  final bool isSubject;
  final ValueChanged<String> onSubmit;

  @override
  State<LoveMapQuestionScreen> createState() => _LoveMapQuestionScreenState();
}

class _LoveMapQuestionScreenState extends State<LoveMapQuestionScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _controller.text.trim();
    if (answer.isEmpty) return;
    widget.onSubmit(answer);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isSubject) ...[
                Text(
                  'Answer honestly about yourself — '
                  'your partner is trying to read you.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
              Text(widget.question.text, style: textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                maxLines: 4,
                maxLength: 400,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: widget.isSubject
                      ? "What's actually true for you right now?"
                      : 'What do you think they would say?',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
