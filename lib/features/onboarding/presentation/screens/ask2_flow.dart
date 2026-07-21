import 'package:attune/core/utils/exports/export_screens.dart';
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
      if (mounted) {
        context.showInfoSnackbar(
          'Saved locally. We will try again the next time you open the app.',
        );
      }
    }

    _next();
  }

  Future<void> _markAsk2StateCompleted() async {
    // ask2_state has no client UPDATE grant (Task 3's migration) — writes go
    // through this SECURITY DEFINER RPC only, same pattern as
    // upsert_attachment_compatibility_cache. Handles both 'prompted' and
    // 'reminded' source states in one call (its WHERE clause covers both).
    //
    // The compatibility pairing itself (upsert_attachment_compatibility_cache
    // — p_relationship_id, p_type_a, p_type_b, p_pairing_name,
    // p_pairing_description, p_natural_strength, p_watch_area) is NOT called
    // here: this task only triggers cache regeneration *eligibility*, it does
    // not compute the pairing content. That computation is the existing
    // Claude-driven compatibility feature (lib/features/quiz/presentation/
    // providers/quiz_providers.dart) and is not yet wired to run
    // automatically on both-partners-complete, so calling the upsert RPC
    // from here would mean inventing placeholder pairing content — out of
    // scope per the design doc.
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
      _ => Ask2RevealStep(onDone: () => Navigator.of(context).maybePop()),
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
