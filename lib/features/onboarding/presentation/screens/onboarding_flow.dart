import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/presentation/eula_gate.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/data/anchors_docs.dart';
import 'package:attune/features/onboarding/presentation/data/attachment_quiz_docs.dart';
import 'package:attune/features/onboarding/presentation/widgets/anchors_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_joined_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_waiting_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_mode_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/personal_ready_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/profile_setup_step.dart';
import 'package:attune/features/relationships/data/relationship_invite_service.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.store,
    required this.onComplete,
    this.acceptedPendingInvite = false,
  });

  final OnboardingStore store;
  final VoidCallback onComplete;

  /// Whether OnboardingGate already accepted a pending couples invite for
  /// this user before mounting this flow (see its _acceptPendingInvite) —
  /// distinguishes "picked couples mode with a partner already linked"
  /// (completedMode: couples, active) from "picked couples mode but no
  /// invite was ever accepted, still waiting for a partner"
  /// (completedMode: couplesPending). Auth + invite acceptance both happen
  /// before this widget exists now (see LoginScreen/OnboardingGate), so
  /// this is the only way _finish can still tell the two apart.
  final bool acceptedPendingInvite;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  // Fixed now that auth (LoginScreen) and invite acceptance (OnboardingGate)
  // both always happen before this widget ever mounts — OnboardingFlow no
  // longer has its own auth step, so these no longer vary by requireAuth.
  static const _profileStep = 0;
  static const _modeStep = 1;
  static const _quizStep = 2;
  static const _anchorsStep = 3;

  final _nameController = TextEditingController();
  final _anchorControllers = List.generate(3, (_) => TextEditingController());
  // Nullable: an unanswered question must be distinguishable from a genuinely
  // neutral one. Pre-filling every item with the midpoint made 26 untouched
  // questions look answered and let a user tap straight through, writing a
  // fabricated all-neutral reflection to onboarding_profiles.
  final _quizAnswers = List<int?>.filled(attachmentQuestions.length, null);
  final _submissionService = OnboardingSubmissionService();
  final _inviteService = RelationshipInviteService();

  OnboardingMode? _mode;
  int _step = 0;
  int _questionIndex = 0;

  @override
  void initState() {
    super.initState();
    // OnboardingGate already accepted this invite before mounting this
    // flow, so mode is already decided — the profile step's onNext (below)
    // skips straight past mode selection once this is set.
    if (widget.acceptedPendingInvite) {
      _mode = OnboardingMode.couples;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _anchorControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() {
    setState(() => _step++);
  }

  /// Couples mode skips straight from mode selection to the terminal
  /// invite/waiting step — the quiz and anchors are Ask 2 now (reached later
  /// via Ask2Flow), not inline here. _step must jump past BOTH the quiz and
  /// anchors slots, not just increment once, since the switch below
  /// dispatches on _step's exact integer value matching quizStep/anchorsStep.
  void _skipToTerminalForCouples() {
    const anchorsStep = 3;
    setState(() => _step = anchorsStep + 1);
  }

  /// A short "ready to move on?" nudge shown before the detailed docs sheet
  /// for a step — so the user opts into reading about what's next (26 quiz
  /// questions, three open anchors) rather than the docs just appearing.
  /// Returns false if the user backs out, in which case the caller must not
  /// proceed to the docs sheet or advance the step.
  Future<bool> _confirmMoveOn({
    required String nextLabel,
    required String message,
    required String confirmText,
    required IconData icon,
  }) async {
    // showDocumentationBottomSheet returns Future<void> — it never surfaces
    // what the user tapped — so confirmation is captured via the dialog's
    // own callbacks instead of a pop value.
    var confirmed = false;
    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      maxHeight: 400.h,
      showButtons: false,
      widget: ConfirmationDialog(
        icon: icon,
        type: ConfirmationType.info,
        title: 'Up next: \n$nextLabel',
        message: message,
        confirmText: confirmText,
        cancelText: 'Not yet',
        onConfirm: () => confirmed = true,
      ),
    );
    return confirmed;
  }

  /// Advances into the quiz, but first explains what it is and why it
  /// matters — otherwise 26 rating questions land with no context.
  Future<void> _goToQuiz() async {
    final proceed = await _confirmMoveOn(
      nextLabel: 'Attachment quiz',
      message:
          'Up next is the attachment quiz — 26 short questions about how you relate to others. It takes about 3-5 minutes.',
      confirmText: 'Understand the quiz',
      icon: Icons.psychology_outlined,
    );
    if (!mounted || !proceed) return;

    final colorScheme = Theme.of(context).colorScheme;
    final docs = AttachmentQuizDocs(mode: _mode);
    // Tapping outside the sheet dismisses it (isDismissible defaults true)
    // without ever running the button's onPressed — the await below resolves
    // either way, so advancing must be gated on an explicit tap, not on the
    // sheet merely closing.
    var startQuiz = false;
    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      showButtons: false,
      widget: Column(
        children: [
          Expanded(
            child: DocumentationTabView(
              module: docs,
              showDocumentationFirst: true,
            ),
          ),
          Gap(Spacing.md.h),
          AppButton(
            textColor: colorScheme.surface,
            label: 'Start quiz',
            onPressed: () {
              startQuiz = true;
              Navigator.of(context).pop();
            },
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
    if (!mounted || !startQuiz) return;
    _next();
  }

  /// Advances into the anchors step, but first explains what an anchor is —
  /// otherwise three open-ended questions land right after the quiz with no
  /// context for why the format suddenly changed.
  Future<void> _goToAnchors() async {
    final proceed = await _confirmMoveOn(
      nextLabel: 'Anchors',
      message:
          'Up next are your anchors — three short questions you answer in your own words. It takes about 2-3 minutes.',
      confirmText: 'Understand anchors',
      icon: Icons.anchor_outlined,
    );
    if (!mounted || !proceed) return;

    final colorScheme = Theme.of(context).colorScheme;
    final docs = AnchorsDocs(mode: _mode);
    // See _goToQuiz: dismissing via tap-outside must not advance — only an
    // explicit tap on the button should.
    var startAnchors = false;
    await BottomSheetUtils.showDocumentationBottomSheet(
      context: context,
      showButtons: false,
      widget: Column(
        children: [
          Expanded(
            child: DocumentationTabView(
              module: docs,
              showDocumentationFirst: true,
            ),
          ),
          Gap(Spacing.md.h),
          AppButton(
            textColor: colorScheme.surface,
            label: 'Start anchors',
            onPressed: () {
              startAnchors = true;
              Navigator.of(context).pop();
            },
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
    if (!mounted || !startAnchors) return;
    _next();
  }

  Future<void> _finish() async {
    final mode = _mode;
    if (mode == null) return;

    final displayName = _nameController.text.trim();
    final anchors =
        _anchorControllers.map((controller) => controller.text.trim()).toList();
    final completedMode =
        mode == OnboardingMode.couples && !widget.acceptedPendingInvite
            ? OnboardingMode.couplesPending
            : mode;
    // The quiz step gates Next on an answer, so by the time we finish every
    // item is set. Drop any nulls rather than fabricate a midpoint.
    final answers = _quizAnswers.whereType<int>().toList();

    // Last gate before an account becomes real. LoginScreen already asks on
    // the sign-in path this flow is always reached through now, but
    // returning/already-accepted users are not re-prompted.
    if (!await _ensureEulaAccepted()) return;

    try {
      await _submissionService.submit(
        mode: completedMode,
        displayName: displayName,
        attachmentAnswers: answers,
        anchors: anchors,
      );
      // Landed remotely — drop any payload left over from an earlier attempt.
      await widget.store.clearPendingSubmission();
    } catch (_) {
      // We still complete locally so a bad network can never trap the user in
      // the flow — but the submission is PERSISTED and replayed on a later
      // launch (OnboardingSyncService). Without that, this "we will sync"
      // message was an empty promise: the user looked onboarded locally while
      // their mode / quiz answers / anchors never reached the server, and the
      // app never re-entered onboarding to try again.
      await widget.store.savePendingSubmission(
        PendingOnboardingSubmission(
          mode: completedMode,
          displayName: displayName,
          attachmentAnswers: answers,
          anchors: anchors,
        ),
      );
      if (mounted) {
        context.showInfoSnackbar(
          'Saved locally. We will sync onboarding when your connection is stable.',
        );
      }
    }

    await widget.store.complete(mode: completedMode, displayName: displayName);
    if (mounted) widget.onComplete();
  }

  /// Consent gate before the account is written remotely.
  Future<bool> _ensureEulaAccepted() async =>
      (await EulaGate.ensureAccepted(context)).mayProceed;

  @override
  Widget build(BuildContext context) {
    final mode = _mode;

    final screen = switch (_step) {
      _ when _step == _profileStep => ProfileSetupStep(
        controller: _nameController,
        // An already-accepted invite means mode is already decided
        // (couples — see initState) — skip the mode-selection question
        // instead of asking something whose answer is already known.
        onNext: widget.acceptedPendingInvite ? _skipToTerminalForCouples : _next,
      ),
      _ when _step == _modeStep => OnboardingModeStep(
        selectedMode: mode,
        onSelect: (value) {
          setState(() => _mode = value);
          if (value == OnboardingMode.personal) {
            _goToQuiz();
          } else {
            _skipToTerminalForCouples();
          }
        },
      ),
      _ when _step == _quizStep => AttachmentQuizStep(
        questionIndex: _questionIndex,
        answers: _quizAnswers,
        onChanged: (value) {
          setState(() => _quizAnswers[_questionIndex] = value);
        },
        onBack:
            _questionIndex == 0 ? null : () => setState(() => _questionIndex--),
        onNext: () {
          if (_questionIndex == attachmentQuestions.length - 1) {
            _goToAnchors();
          } else {
            setState(() => _questionIndex++);
          }
        },
      ),
      _ when _step == _anchorsStep => AnchorsStep(
        mode: mode ?? OnboardingMode.personal,
        controllers: _anchorControllers,
        onNext: _next,
      ),
      _ =>
        mode == OnboardingMode.couples
            ? widget.acceptedPendingInvite
                ? CouplesJoinedStep(onFinish: _finish)
                : CouplesWaitingStep(
                  inviteService: _inviteService,
                  onFinish: _finish,
                )
            : PersonalReadyStep(onFinish: _finish),
    };

    // One card-identity per visible card: the quiz stays on a single outer
    // _step across all 26 questions, so its sub-index is folded in here too —
    // otherwise only the first quiz question would ever play the flip.
    final cardKey =
        _step == _quizStep ? _quizStep * 1000 + _questionIndex : _step;

    final accent = switch (mode) {
      OnboardingMode.personal => OnboardingDeckAccent.single,
      OnboardingMode.couples ||
      OnboardingMode.couplesPending => OnboardingDeckAccent.couples,
      null => OnboardingDeckAccent.neutral,
    };

    return Scaffold(
      body: SafeArea(
        child: OnboardingDeckScope(
          cardKey: cardKey,
          accent: accent,
          // Only the attachment quiz gets the fanned card stack; name, mode
          // choice, anchors, and terminal steps render as plain cards.
          enableDeck: _step == _quizStep,
          child: screen,
        ),
      ),
    );
  }
}
