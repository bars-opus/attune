import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/presentation/passwordless_auth_step.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/data/anchors_docs.dart';
import 'package:attune/features/onboarding/presentation/data/attachment_quiz_docs.dart';
import 'package:attune/features/onboarding/presentation/widgets/anchors_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_joined_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_waiting_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/incoming_invite_step.dart';
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
    this.requireAuth = true,
    RelationshipInviteService? inviteService,
  }) : _inviteService = inviteService;

  final OnboardingStore store;
  final VoidCallback onComplete;
  final bool requireAuth;
  final RelationshipInviteService? _inviteService;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _nameController = TextEditingController();
  final _anchorControllers = List.generate(3, (_) => TextEditingController());
  // Nullable: an unanswered question must be distinguishable from a genuinely
  // neutral one. Pre-filling every item with the midpoint made 26 untouched
  // questions look answered and let a user tap straight through, writing a
  // fabricated all-neutral reflection to onboarding_profiles.
  final _quizAnswers = List<int?>.filled(attachmentQuestions.length, null);
  final _submissionService = OnboardingSubmissionService();
  late final RelationshipInviteService _inviteService =
      widget._inviteService ?? RelationshipInviteService();

  OnboardingMode? _mode;
  int _step = 0;
  int _questionIndex = 0;
  bool _isAcceptingInvite = false;
  bool _acceptedPendingInvite = false;

  String? get _pendingInviteCode => widget.store.pendingInviteCode;

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
    final anchorsStep = widget.requireAuth ? 4 : 3;
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
              documentation: docs.getSections(context),
              faqs: docs.getFAQs(context),
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
              documentation: docs.getSections(context),
              faqs: docs.getFAQs(context),
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
        mode == OnboardingMode.couples && !_acceptedPendingInvite
            ? OnboardingMode.couplesPending
            : mode;
    // The quiz step gates Next on an answer, so by the time we finish every
    // item is set. Drop any nulls rather than fabricate a midpoint.
    final answers = _quizAnswers.whereType<int>().toList();

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

  Future<void> _handleAuthVerified() async {
    final inviteCode = _pendingInviteCode;
    if (inviteCode == null || _acceptedPendingInvite) {
      _next();
      return;
    }

    if (_isAcceptingInvite) return;

    setState(() => _isAcceptingInvite = true);

    try {
      await _inviteService.acceptInvite(inviteCode);
      await widget.store.clearPendingInviteCode();
      if (!mounted) return;
      setState(() {
        _acceptedPendingInvite = true;
        _isAcceptingInvite = false;
      });
      _next();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isAcceptingInvite = false);
      final message =
          error is RelationshipInviteException
              ? error.message
              : 'Could not accept this invite yet.';
      context.showErrorSnackbar('$message Try verification again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final pendingInviteCode = _pendingInviteCode;
    final profileStep = widget.requireAuth ? 1 : 0;
    final modeStep = widget.requireAuth ? 2 : 1;
    final quizStep = widget.requireAuth ? 3 : 2;
    final anchorsStep = widget.requireAuth ? 4 : 3;

    final screen = switch (_step) {
      0 when widget.requireAuth => Stack(
        children: [
          PasswordlessAuthStep(onVerified: _handleAuthVerified),
          if (_isAcceptingInvite)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.4),
                child: const Center(child: CircularLoadingIndicator()),
              ),
            ),
        ],
      ),
      _ when _step == profileStep => ProfileSetupStep(
        controller: _nameController,
        onNext: _next,
      ),
      _ when _step == modeStep =>
        pendingInviteCode == null
            ? OnboardingModeStep(
              selectedMode: mode,
              onSelect: (value) {
                setState(() => _mode = value);
                if (value == OnboardingMode.personal) {
                  _goToQuiz();
                } else {
                  _skipToTerminalForCouples();
                }
              },
            )
            : IncomingInviteStep(
              inviteCode: pendingInviteCode,
              onNext: () {
                setState(() => _mode = OnboardingMode.couples);
                _skipToTerminalForCouples();
              },
            ),
      _ when _step == quizStep => AttachmentQuizStep(
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
      _ when _step == anchorsStep => AnchorsStep(
        mode: mode ?? OnboardingMode.personal,
        controllers: _anchorControllers,
        onNext: _next,
      ),
      _ =>
        mode == OnboardingMode.couples
            ? _acceptedPendingInvite
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
        _step == quizStep ? quizStep * 1000 + _questionIndex : _step;

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
          enableDeck: _step == quizStep,
          child: screen,
        ),
      ),
    );
  }
}
