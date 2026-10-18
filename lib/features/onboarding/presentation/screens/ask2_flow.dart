import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/onboarding/data/ask2_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/anchors_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/ask2_reveal_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/intelligence_intro_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ask 2 (ATTUNE_MASTER_SPEC.md decision 29) — reached only via the deep
/// link a notification sends once a couple is eligible (see
/// evaluate-ask2-eligibility). NOT a mode of OnboardingFlow: Ask 1 is
/// already complete by the time this is reachable, so this is a fully
/// separate, small state machine that composes the SAME quiz/anchors step
/// widgets Ask 1 uses for personal mode, so fixes to those widgets apply
/// to both automatically.
class Ask2Flow extends StatefulWidget {
  const Ask2Flow({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  State<Ask2Flow> createState() => _Ask2FlowState();
}

class _Ask2FlowState extends State<Ask2Flow> {
  static const int _introStep = 0;
  static const int _quizStep = 1;
  static const int _anchorsStep = 2;
  static const int _revealStep = 3;

  final _anchorControllers = List.generate(3, (_) => TextEditingController());
  final _quizAnswers = List<int?>.filled(attachmentQuestions.length, null);
  final _submissionService = Ask2SubmissionService();

  int _step = _introStep;
  int _questionIndex = 0;

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
      await _submissionService.submit(attachmentAnswers: answers, anchors: anchors);
      await _markAsk2StateCompleted();
    } catch (_) {
      // TODO: Ask 2 has no persistence/retry layer yet (unlike Ask 1's
      // OnboardingFlow with PendingOnboardingSubmission + OnboardingSyncService).
      // If submission fails here, answers are genuinely lost. Future task should
      // implement proper recovery mechanism.
      if (mounted) {
        context.showInfoSnackbar(
          'Something went wrong saving your answers. You can try again from the notification that brought you here.',
        );
      }
    }

    _next();
  }

  Future<void> _markAsk2StateCompleted() async {
    // ask2_state has no client UPDATE grant (Task 3's migration) — writes go
    // through this SECURITY DEFINER RPC only. Handles both 'prompted' and
    // 'reminded' source states in one call (its WHERE clause covers both).
    //
    // Spec 5 (F9): no compatibility pairing is ever computed or shown; the
    // reward is the person's own anchors reflected back (Ask2RevealStep).
    await Supabase.instance.client.rpc(
      'complete_ask2',
      params: {'p_relationship_id': widget.relationshipId},
    );
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
