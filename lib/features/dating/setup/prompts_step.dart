// Spec 2 §3.2 D10 (Step 9 of 12): two of ten prompts (a third optional),
// 10-200 characters each, each a labelled field with its count; the
// server's contact mask and S1 W9a's pre-post filter
// (private.content_filter_verdict, answered contact_details / unkind with
// the prompt's position) land on their own prompt.
//
// T10 carry F (the step frame as it is now): each prompt is its own field,
// so a saved answer that arrives after the person ticked or typed fills
// every prompt they haven't touched and never overwrites one they have;
// Continue waits for the saved answers (never a save over ones the screen
// couldn't read); a failed read is the error row with Retry; the mixin's
// write sends one request per tap burst and settles its key.
//
// Fix round 1: the server's own text rules are checked first and said under
// the answer that breaks them (I-2: a joined emoji or another invisible
// character, too short after the trim, no letter or number); the length is
// counted as the server counts it, code points (M-5); a refusal stays with
// the prompt it was about, whatever is ticked after (M-6).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/dating_text_rules.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const datingPromptIds = [
  'perfect_sunday',
  'feel_at_home',
  'friends_say',
  'looking_for',
  'small_thing',
  'win_me_over',
  'learning_to',
  'family_describe',
  'place_love',
  'ask_me_about',
];

String datingPromptText(AppLocalizations loc, String id) => switch (id) {
  'perfect_sunday' => loc.dating_prompt_perfect_sunday,
  'feel_at_home' => loc.dating_prompt_feel_at_home,
  'friends_say' => loc.dating_prompt_friends_say,
  'looking_for' => loc.dating_prompt_looking_for,
  'small_thing' => loc.dating_prompt_small_thing,
  'win_me_over' => loc.dating_prompt_win_me_over,
  'learning_to' => loc.dating_prompt_learning_to,
  'family_describe' => loc.dating_prompt_family_describe,
  'place_love' => loc.dating_prompt_place_love,
  _ => loc.dating_prompt_ask_me_about,
};

class DatingPromptsStep extends ConsumerStatefulWidget {
  const DatingPromptsStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPromptsStep> createState() => _DatingPromptsStepState();
}

class _DatingPromptsStepState extends ConsumerState<DatingPromptsStep>
    with DatingStepState<DatingPromptsStep> {
  final _chosen = <String>[];
  final _answers = <String, TextEditingController>{};

  /// The line under each answer the device refused before sending (I-2).
  final _problems = <String, String>{};

  /// The prompts as last sent: a refusal's position names one of them
  /// (M-6).
  List<String> _sent = const [];

  TextEditingController _controller(String id) =>
      _answers.putIfAbsent(id, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void resetAnswers() {
    _chosen.clear();
    for (final c in _answers.values) {
      c.clear();
    }
    _problems.clear();
    _sent = const [];
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    for (final (id, answer) in p.prompts) {
      if (!datingPromptIds.contains(id)) continue;
      if (!isTouched('pick_$id') &&
          !_chosen.contains(id) &&
          _chosen.length < 3) {
        _chosen.add(id);
      }
      if (!isTouched('text_$id')) _controller(id).text = answer;
    }
  }

  /// What the server would refuse in [text], in words; null when fine.
  String? _problem(AppLocalizations loc, String text) {
    if (datingHasInvisible(text)) return loc.dating_textInvisible;
    final length = datingTextLength(text);
    if (length < 10 || length > 200) return loc.dating_promptTooShort;
    if (!datingHasWord(text)) return loc.dating_promptNeedsWords;
    return null;
  }

  void _continue() {
    final loc = AppLocalizations.of(context)!;
    final problems = {
      for (final id in _chosen)
        if (_problem(loc, _controller(id).text) case final p?) id: p,
    };
    setState(() {
      _problems
        ..clear()
        ..addAll(problems);
    });
    if (_chosen.length < 2 || problems.isNotEmpty) return;
    final items = [for (final id in _chosen) (id, _controller(id).text.trim())];
    _sent = [for (final (id, _) in items) id];
    write(
      'd10',
      items,
      (key) => ref.read(datingSetupGatewayProvider).savePrompts(key, items),
      (w) => widget.nav.next(w.nextStep ?? 'verify'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final theme = Theme.of(context);
    final at = refusal?.position;
    // The refused prompt by id, as sent (M-6).
    final refusedId =
        at != null && at >= 1 && at <= _sent.length ? _sent[at - 1] : null;
    return DatingStepFrame(
      step: 'prompts',
      title: loc.dating_promptsTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_promptsBody, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Spacing.md),
          if (profileFailed)
            DatingLoadError(busy: profileRetrying, onRetry: retryProfile),
          for (final id in datingPromptIds) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(datingPromptText(loc, id)),
              value: _chosen.contains(id),
              onChanged:
                  _chosen.contains(id) || _chosen.length < 3
                      ? (v) => answer([
                        'pick_$id',
                      ], () => v == true ? _chosen.add(id) : _chosen.remove(id))
                      : null,
            ),
            if (_chosen.contains(id))
              Column(
                key: ValueKey('dating_prompt_${id}_block'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: _controller(id),
                    builder:
                        (context, _) => TextField(
                          key: ValueKey('dating_prompt_$id'),
                          controller: _controller(id),
                          // Final fix (M-12): the keyboard learns nothing typed here.
                          enableSuggestions: false,
                          autocorrect: false,
                          enableIMEPersonalizedLearning: false,
                          onChanged: (_) => answer(['text_$id'], () {}),
                          // As the server counts: code points (M-5).
                          inputFormatters: const [DatingRuneLimit(200)],
                          minLines: 2,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: datingPromptText(loc, id),
                            counterText: loc.dating_gentleWaitAnswerCount(
                              _controller(id).text.runes.length,
                              200,
                            ),
                          ),
                        ),
                  ),
                  if (_problems[id] case final problem?)
                    FlowErrorLine(text: problem, liveRegion: true),
                  if (refusedId == id) datingRefusalLine(loc, refusal!),
                ],
              ),
          ],
          if (refusal != null && refusedId == null)
            datingRefusalLine(loc, refusal!),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        // Never over saved answers the screen couldn't read (carry F).
        onPressed:
            online && profileReady && _chosen.length >= 2 ? _continue : null,
      ),
    );
  }
}
