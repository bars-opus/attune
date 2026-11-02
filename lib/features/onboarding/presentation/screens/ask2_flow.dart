import 'dart:async';
import 'dart:convert';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/onboarding/data/ask2_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/anchors_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/ask2_reveal_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/intelligence_intro_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ask 2 (ATTUNE_MASTER_SPEC.md decision 29) — reached only via the deep
/// link a notification sends once a couple is eligible (see
/// evaluate-ask2-eligibility). NOT a mode of OnboardingFlow: Ask 1 is
/// already complete by the time this is reachable, so this is a fully
/// separate, small state machine that composes the SAME quiz/anchors step
/// widgets Ask 1 uses for personal mode, so fixes to those widgets apply
/// to both automatically.
///
/// Ask 2's server write: the answers, then complete_ask2 (batch-6 review
/// M-3: replaceable in tests).
typedef Ask2Finish =
    Future<void> Function(
      String relationshipId,
      List<int> answers,
      List<String> anchors,
    );

final ask2FinishProvider = Provider<Ask2Finish>(
  (ref) => (relationshipId, answers, anchors) async {
    await Ask2SubmissionService().submit(
      attachmentAnswers: answers,
      anchors: anchors,
    );
    // ask2_state has no client UPDATE grant (Task 3's migration) — writes go
    // through this SECURITY DEFINER RPC only. Handles both 'prompted' and
    // 'reminded' source states in one call (its WHERE clause covers both).
    //
    // Spec 5 (F9): no compatibility pairing is ever computed or shown; the
    // reward is the person's own anchors reflected back (Ask2RevealStep).
    await Supabase.instance.client.rpc(
      'complete_ask2',
      params: {'p_relationship_id': relationshipId},
    );
  },
);

/// Spec 1 W4b (§3.8 R5): every answer and anchor is saved on this phone as
/// it is given (Ask2ProgressStore); reopening resumes at the first
/// unanswered item; the saved progress goes on completion, and with the
/// sign-out and quick-exit wipes.
class Ask2Flow extends ConsumerStatefulWidget {
  const Ask2Flow({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<Ask2Flow> createState() => _Ask2FlowState();
}

class _Ask2FlowState extends ConsumerState<Ask2Flow> {
  static const int _introStep = 0;
  static const int _quizStep = 1;
  static const int _anchorsStep = 2;
  static const int _revealStep = 3;

  final _anchorControllers = List.generate(3, (_) => TextEditingController());
  final _quizAnswers = List<int?>.filled(attachmentQuestions.length, null);

  int _step = _introStep;
  int _questionIndex = 0;

  /// Null when there's no account or no SharedPreferences (nothing saved).
  Ask2ProgressStore? _progress;

  /// What was last written, so a selection move writes nothing (M-3).
  String? _saved;

  /// Set once the answers reached the server: nothing is saved after.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _progress = _progressStore();
    final saved = _progress?.read(
      questionCount: attachmentQuestions.length,
      anchorCount: _anchorControllers.length,
    );
    if (saved != null) {
      for (var i = 0; i < saved.answers.length; i++) {
        _quizAnswers[i] = saved.answers[i];
      }
      for (var i = 0; i < saved.anchors.length; i++) {
        _anchorControllers[i].text = saved.anchors[i];
      }
      final next = saved.firstUnanswered;
      _step = next == null ? _anchorsStep : _quizStep;
      _questionIndex = next ?? attachmentQuestions.length - 1;
    }
    for (final controller in _anchorControllers) {
      controller.addListener(_save);
    }
  }

  Ask2ProgressStore? _progressStore() {
    try {
      final userId = ref.read(homeAuthProvider).currentUser?.id;
      if (userId == null || userId.isEmpty) return null;
      return Ask2ProgressStore(
        ref.read(sharedPreferencesProvider),
        userId: userId,
        relationshipId: widget.relationshipId,
      );
    } catch (_) {
      return null;
    }
  }

  void _save() {
    final progress = _progress;
    if (progress == null || _finished) return;
    final next = Ask2Progress(
      answers: List<int?>.of(_quizAnswers),
      anchors: [for (final c in _anchorControllers) c.text],
    );
    final shape = jsonEncode([next.answers, next.anchors]);
    if (shape == _saved) return;
    _saved = shape;
    unawaited(progress.write(next));
  }

  @override
  void dispose() {
    for (final controller in _anchorControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() => setState(() => _step++);

  Future<void> _finish() async {
    final answers = _quizAnswers.whereType<int>().toList();
    final anchors =
        _anchorControllers.map((controller) => controller.text.trim()).toList();

    try {
      await ref.read(ask2FinishProvider)(
        widget.relationshipId,
        answers,
        anchors,
      );
      // Done: nothing is owed any more (§3.8 R5). A failure keeps it, so
      // reopening resumes with every answer.
      _finished = true;
      await _progress?.clear();
    } catch (_) {
      // Spec 1 W4b (§3.8 R5): the answers stay saved on this phone
      // (Ask2ProgressStore), so reopening Ask 2 resumes with every one of
      // them; the server write is retried from there.
      if (mounted) {
        context.showInfoSnackbar(
          'Something went wrong saving your answers. You can try again from the notification that brought you here.',
        );
      }
    }

    _next();
  }

  @override
  Widget build(BuildContext context) {
    final screen = switch (_step) {
      _introStep => IntelligenceIntroStep(onNext: _next),
      _quizStep => AttachmentQuizStep(
        questionIndex: _questionIndex,
        answers: _quizAnswers,
        onChanged: (value) {
          setState(() => _quizAnswers[_questionIndex] = value);
          _save();
        },
        onBack:
            _questionIndex == 0 ? null : () => setState(() => _questionIndex--),
        onNext: () {
          if (_questionIndex == attachmentQuestions.length - 1) {
            _next();
          } else {
            setState(() => _questionIndex++);
          }
        },
      ),
      _anchorsStep => AnchorsStep(
        mode: OnboardingMode.couples,
        controllers: _anchorControllers,
        onNext: _finish,
      ),
      _ => Ask2RevealStep(
        anchors: _anchorControllers.map((c) => c.text).toList(),
        // Spec 8 (F14, review §1.8): the private check-in is offered once
        // here, skippable, and never stored with Ask-2.
        onDone: () async {
          await offerSafetySelfCheck(context);
          if (context.mounted) Navigator.of(context).maybePop();
        },
        onLoveMap: () => context.push(RouteNames.loveMap),
        onThisOrThat: () => context.push(RouteNames.thisOrThatGamesHub),
      ),
    };

    final cardKey = _step == _quizStep ? _quizStep * 1000 + _questionIndex : _step;

    return Scaffold(
      body: SafeArea(
        child: OnboardingDeckScope(
          cardKey: cardKey,
          accent: OnboardingDeckAccent.couples,
          enableDeck: _step == _quizStep,
          child: screen,
        ),
      ),
    );
  }
}
