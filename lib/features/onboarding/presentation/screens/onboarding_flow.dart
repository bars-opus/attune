import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/auth/presentation/passwordless_auth_step.dart';
import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/anchors_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_joined_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/couples_waiting_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/incoming_invite_step.dart';
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
  final _quizAnswers = List<int>.filled(attachmentQuestions.length, 3);
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

    try {
      await _submissionService.submit(
        mode: completedMode,
        displayName: displayName,
        attachmentAnswers: _quizAnswers,
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
          attachmentAnswers: _quizAnswers,
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
                _next();
              },
            )
            : IncomingInviteStep(
              inviteCode: pendingInviteCode,
              onNext: () {
                setState(() => _mode = OnboardingMode.couples);
                _next();
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
            _next();
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

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: AnimationDurations.fast,
          switchInCurve: AnimationCurves.standard,
          switchOutCurve: AnimationCurves.standard,
          child: screen,
        ),
      ),
    );
  }
}
