// lib/features/games/paint_ball/presentation/screens/paint_ball_knockout_screen.dart

import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/presence/breathing_dots.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/paint_ball/models/paint_ball_models.dart';
import 'package:attune/features/games/paint_ball/presentation/state/paint_ball_provider.dart';
import 'package:attune/features/games/paint_ball/presentation/widgets/paint_ball_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaintBallKnockoutScreen extends ConsumerStatefulWidget {
  const PaintBallKnockoutScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<PaintBallKnockoutScreen> createState() =>
      _PaintBallKnockoutScreenState();
}

class _PaintBallKnockoutScreenState
    extends ConsumerState<PaintBallKnockoutScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _entryController;
  bool _entryStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(paintBallSessionProvider.notifier).loadSession(widget.sessionId);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entryStarted) return;
    _entryStarted = true;
    if (reduceMotionOf(context)) {
      _entryController.value = 1;
    } else {
      unawaited(_entryController.forward());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        ref
            .read(paintBallSessionProvider.notifier)
            .loadSession(widget.sessionId),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(paintBallSessionProvider);
    final session = state.session;

    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final currentUserId = ref.watch(paintBallCurrentUserIdProvider);
    final isWinner = session.winnerUserId == currentUserId;
    final isLoser = session.winnerUserId != null && !isWinner;
    final isResolved =
        session.isCompleted ||
        session.penaltyStatus == 'completed' ||
        session.penaltyStatus == 'declined';

    return Scaffold(
      appBar: AppBar(
        title: Text(isResolved ? 'Paint Ball' : 'Truth or Dare'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed:
              () => Navigator.of(context).pop(PaintBallExitAction.backToChat),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _entryController,
            curve: Curves.easeOut,
          ),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: _entryController,
                curve: Curves.easeOutCubic,
              ),
            ),
            child:
                isResolved
                    ? _PaintBallEndView(
                      session: session,
                      currentUserId: currentUserId,
                    )
                    : isWinner
                    ? _WinnerWaitingView(session: session)
                    : _PenaltyView(
                      session: session,
                      isLoser: isLoser,
                      isSubmitting: state.isSubmitting,
                      errorMessage: state.errorMessage,
                    ),
          ),
        ),
      ),
    );
  }
}

class _KnockoutMark extends StatelessWidget {
  const _KnockoutMark({required this.loser});

  final bool loser;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = loser ? PaintBallPalette.theirs : PaintBallPalette.mine;

    return Semantics(
      label:
          loser
              ? 'You have no lives remaining'
              : 'Your partner has no lives remaining',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (_) => Container(
                  width: 22.w,
                  height: 22.w,
                  margin: EdgeInsets.symmetric(horizontal: 4.w),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.44),
                      width: 1.5.r,
                    ),
                  ),
                ),
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              loser ? 'KNOCKED OUT' : 'FINAL HIT',
              style: textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PenaltyView extends ConsumerWidget {
  const _PenaltyView({
    required this.session,
    required this.isLoser,
    required this.isSubmitting,
    required this.errorMessage,
  });

  final PaintBallSessionState session;
  final bool isLoser;
  final bool isSubmitting;
  final String? errorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final penaltyType = session.penaltyType == 'dare' ? 'Dare' : 'Truth';
    final prompt = session.penaltyPromptSnapshot?.trim() ?? '';

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.lg.h,
        Spacing.lg.w,
        Spacing.xxl.h,
      ),
      children: [
        const _KnockoutMark(loser: true),
        Gap(Spacing.xl.h),
        Text(
          'One last moment',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Gap(Spacing.xs.h),
        Text(
          'Complete it if it feels fun, or skip it freely.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        Gap(Spacing.xl.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(Spacing.lg.w),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            children: [
              Text(
                penaltyType.toUpperCase(),
                style: textTheme.labelLarge?.copyWith(
                  color:
                      penaltyType == 'Truth'
                          ? PaintBallPalette.mine
                          : PaintBallPalette.theirs,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              Gap(Spacing.md.h),
              Text(
                prompt.isEmpty
                    ? 'This prompt could not be loaded. You can skip and finish the game.'
                    : prompt,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(height: 1.35),
              ),
            ],
          ),
        ),
        Gap(Spacing.lg.h),
        if (isLoser)
          if (isSubmitting)
            const Center(child: CircularProgressIndicator())
          else ...[
            AppButton(
              label: 'Complete',
              onPressed:
                  prompt.isEmpty
                      ? null
                      : () => ref
                          .read(paintBallSessionProvider.notifier)
                          .resolvePenalty(completed: true),
              width: double.infinity,
              size: ButtonSize.medium,
              animateButton: !reduceMotionOf(context),
            ),
            Gap(Spacing.sm.h),
            AppButton(
              label: 'Skip this one',
              onPressed:
                  () => ref
                      .read(paintBallSessionProvider.notifier)
                      .resolvePenalty(completed: false),
              width: double.infinity,
              size: ButtonSize.medium,
              variant: ButtonVariant.text,
              animateButton: !reduceMotionOf(context),
            ),
          ],
        if (errorMessage != null) ...[
          Gap(Spacing.md.h),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
        Gap(Spacing.xl.h),
        Text(
          'Skipping changes nothing between you and is never recorded as something owed.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.48),
          ),
        ),
      ],
    );
  }
}

class _WinnerWaitingView extends StatelessWidget {
  const _WinnerWaitingView({required this.session});

  final PaintBallSessionState session;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final type = session.penaltyType == 'dare' ? 'dare' : 'truth';

    return Padding(
      padding: EdgeInsets.all(Spacing.lg.w),
      child: Column(
        children: [
          const Spacer(),
          const _KnockoutMark(loser: false),
          Gap(Spacing.xl.h),
          Text(
            'You read them right.',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Gap(Spacing.sm.h),
          Text(
            'Your partner has a $type prompt they can complete or skip. Both choices are completely fine.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.64),
            ),
          ),
          Gap(Spacing.xl.h),
          const BreathingDots(size: 7),
          Gap(Spacing.sm.h),
          Text(
            'Waiting for them to wrap up',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.52),
            ),
          ),
          const Spacer(),
          AppButton(
            label: 'Back to chat',
            onPressed:
                () => Navigator.of(context).pop(PaintBallExitAction.backToChat),
            variant: ButtonVariant.outline,
            size: ButtonSize.medium,
            width: double.infinity,
            animateButton: !reduceMotionOf(context),
          ),
        ],
      ),
    );
  }
}

class _PaintBallEndView extends ConsumerWidget {
  const _PaintBallEndView({required this.session, required this.currentUserId});

  final PaintBallSessionState session;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final iWon = session.winnerUserId == currentUserId;
    final myHits = _hitsFor(currentUserId);
    final partnerId =
        currentUserId == session.userAId ? session.userBId : session.userAId;
    final partnerHits = _hitsFor(partnerId);
    final skipped = session.penaltyStatus == 'declined';

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg.w,
        Spacing.xl.h,
        Spacing.lg.w,
        Spacing.xxl.h,
      ),
      children: [
        Icon(
          Icons.colorize_rounded,
          size: 44.h,
          color: PaintBallPalette.player,
        ),
        Gap(Spacing.md.h),
        Text(
          'Nice read.',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Gap(Spacing.xs.h),
        Text(
          iWon
              ? 'You landed the final hit.'
              : 'Your partner landed the final hit.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        Gap(Spacing.xl.h),
        Container(
          padding: EdgeInsets.all(Spacing.lg.w),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            children: [
              _RecapRow(label: 'Your hits', value: '$myHits'),
              Gap(Spacing.md.h),
              _RecapRow(label: 'Their hits', value: '$partnerHits'),
              Gap(Spacing.md.h),
              _RecapRow(
                label: session.penaltyType == 'dare' ? 'Dare' : 'Truth',
                value: skipped ? 'Skipped' : 'Completed',
              ),
            ],
          ),
        ),
        Gap(Spacing.xl.h),
        AppButton(
          label: 'Play again',
          onPressed: () {
            Navigator.of(context).pop(PaintBallExitAction.playAgain);
          },
          width: double.infinity,
          size: ButtonSize.medium,
          animateButton: !reduceMotionOf(context),
        ),
        Gap(Spacing.sm.h),
        AppButton(
          label: 'Try another game',
          onPressed: () {
            ref.read(paintBallSessionProvider.notifier).reset();
            Navigator.of(context).pop(PaintBallExitAction.openGames);
          },
          width: double.infinity,
          size: ButtonSize.medium,
          variant: ButtonVariant.outline,
          animateButton: !reduceMotionOf(context),
        ),
        Gap(Spacing.md.h),
        Text(
          'This recap belongs only to this game. Attune does not keep a running score.',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.46),
          ),
        ),
      ],
    );
  }

  int _hitsFor(String? userId) =>
      session.rounds
          .where(
            (round) =>
                round.activePartnerId == userId &&
                round.outcome == PaintBallShotOutcome.hit,
          )
          .length;
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
