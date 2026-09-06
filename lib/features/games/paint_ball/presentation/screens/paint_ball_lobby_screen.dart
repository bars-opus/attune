// lib/features/games/paint_ball/presentation/screens/paint_ball_lobby_screen.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/ui/motion/reduce_motion.dart';
import '../../../../../core/utils/exports/export_screens.dart';
import '../../models/paint_ball_models.dart';
import '../state/paint_ball_provider.dart';
import '../widgets/paint_ball_field.dart';

class PaintBallLobbyScreen extends ConsumerStatefulWidget {
  final String relationshipId;

  const PaintBallLobbyScreen({super.key, required this.relationshipId});

  @override
  ConsumerState<PaintBallLobbyScreen> createState() =>
      _PaintBallLobbyScreenState();
}

class _PaintBallLobbyScreenState extends ConsumerState<PaintBallLobbyScreen> {
  String _selectedTone = 'playful';
  bool _allowPartnerPrompts = false;
  bool _routing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(paintBallSessionProvider);
      final session = state.session;
      if (session != null &&
          session.relationshipId == widget.relationshipId &&
          !session.isCompleted &&
          !session.isAbandoned) {
        unawaited(_routeForPhase(state.phase, session.sessionId));
        return;
      }
      if (session?.isCompleted == true || session?.isAbandoned == true) {
        ref.read(paintBallSessionProvider.notifier).reset();
      }
      // No session in memory yet — check the backend for a resumable one (an
      // incoming invite for this partner, or a game in progress to rejoin).
      ref
          .read(paintBallSessionProvider.notifier)
          .loadActiveSession(widget.relationshipId);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaintBallGamePhase>(paintBallGamePhaseProvider, (
      previous,
      next,
    ) {
      final sessionId = ref.read(paintBallCurrentSessionProvider)?.sessionId;
      if (sessionId != null) {
        unawaited(_routeForPhase(next, sessionId));
      }
    });

    final state = ref.watch(paintBallSessionProvider);
    final notifier = ref.read(paintBallSessionProvider.notifier);
    final currentUserId = ref.watch(paintBallCurrentUserIdProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final session = state.session;

    // An incoming invite: an existing 'invited' session this user did NOT
    // initiate. Without an accept/decline path the game can never leave the
    // invited state, so the invited partner gets Accept / Decline here.
    final isIncomingInvite =
        session != null &&
        session.relationshipId == widget.relationshipId &&
        session.isInvited &&
        currentUserId != null &&
        session.initiatorId != currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paint Ball'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Paint Ball history',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => unawaited(_openHistory()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Spacing.lg.w,
            Spacing.md.h,
            Spacing.lg.w,
            Spacing.xxl.h,
          ),
          children: [
            Text(
              'Paint Ball',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'A quick read on the person you know best',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.xl.h),
            IgnorePointer(
              child: PaintBallField(
                splats: const [],
                myPosition: 1,
                selectedShot: 2,
                revealedPartnerPosition: null,
                isMyTurn: false,
              ),
            ),
            Gap(Spacing.lg.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'How it works',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'Choose where to hide and where you think your partner hid. '
                    'A correct read removes one life; every reveal gives you a '
                    'clue for the next turn.',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  Gap(Spacing.md.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFeature('3', 'Lives', colorScheme),
                      _buildFeature('2', 'Choices', colorScheme),
                      _buildFeature('1', 'Prompt', colorScheme),
                    ],
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),
            if (session == null) ...[
              Text('Choose your tone', style: textTheme.titleMedium),
              Gap(Spacing.sm.h),
              Wrap(
                spacing: Spacing.sm.w,
                runSpacing: Spacing.sm.h,
                children: [
                  _buildToneChip('Playful', 'playful'),
                  _buildToneChip('Connecting', 'connecting'),
                  _buildToneChip('Romantic', 'romantic'),
                ],
              ),
              Gap(Spacing.md.h),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _allowPartnerPrompts,
                onChanged: (value) {
                  setState(() => _allowPartnerPrompts = value);
                },
                title: const Text('Include shared partner prompts'),
                subtitle: const Text(
                  'If none fit this tone, Attune uses its own prompt instead.',
                ),
              ),
              Gap(Spacing.lg.h),
            ],
            if (session != null &&
                session.relationshipId == widget.relationshipId) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  session.isInvited
                      ? isIncomingInvite
                          ? 'Your partner invited you to play at the ${session.tone} tone.'
                          : 'Invitation sent. Your partner can answer whenever they are ready.'
                      : session.hasPendingPenalty
                      ? 'Penalty is ready.'
                      : session.isActive
                      ? 'Game in progress.'
                      : 'Session complete.',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Gap(Spacing.md.h),
            ],
            if (state.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (isIncomingInvite)
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Decline',
                      onPressed: () async {
                        await notifier.declineSession(session.sessionId);
                        if (!context.mounted) return;
                        final declined =
                            ref
                                .read(paintBallSessionProvider)
                                .session
                                ?.isAbandoned;
                        if (declined == true) {
                          Navigator.of(context).maybePop();
                        }
                      },
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      animateButton: !reduceMotionOf(context),
                    ),
                  ),
                  Gap(Spacing.md.w),
                  Expanded(
                    child: AppButton(
                      label: 'Accept',
                      onPressed:
                          () => notifier.acceptSession(session.sessionId),
                      size: ButtonSize.small,
                      animateButton: !reduceMotionOf(context),
                    ),
                  ),
                ],
              )
            else if (session?.isInvited == true)
              AppButton(
                label: 'Back to chat',
                onPressed: () => Navigator.of(context).maybePop(),
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                width: double.infinity,
                animateButton: !reduceMotionOf(context),
              )
            else
              AppButton(
                label: session == null ? 'Start game' : 'Resume game',
                onPressed: () async {
                  if (session != null) {
                    await _routeForPhase(state.phase, session.sessionId);
                    return;
                  }
                  await notifier.createSession(
                    relationshipId: widget.relationshipId,
                    tone: _selectedTone,
                    allowPartnerAuthored: _allowPartnerPrompts,
                  );
                },
                size: ButtonSize.small,
                width: double.infinity,
                animateButton: !reduceMotionOf(context),
              ),
            Gap(Spacing.sm.h),
            if (state.errorMessage != null)
              Text(
                state.errorMessage!,
                style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(String label, String caption, ColorScheme colorScheme) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
          ),
        ),
        Gap(Spacing.xs.h),
        Text(
          caption,
          style: TextStyle(
            fontSize: FontSizeTokens.sm,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildToneChip(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selectedTone == value;

    return GestureDetector(
      onTap: () => setState(() => _selectedTone = value),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.sm.h,
        ),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: BorderWidthTokens.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Future<void> _openHistory() async {
    final action = await context.pushNamed<PaintBallExitAction>(
      'paintBallHistory',
      pathParameters: {'relationshipId': widget.relationshipId},
    );
    if (!mounted ||
        action == null ||
        action == PaintBallExitAction.backToChat) {
      return;
    }
    if (action == PaintBallExitAction.playAgain) {
      ref.read(paintBallSessionProvider.notifier).reset();
      return;
    }
    Navigator.of(context).pop(action);
  }

  Future<void> _routeForPhase(
    PaintBallGamePhase phase,
    String sessionId,
  ) async {
    if (!mounted || _routing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    final route = switch (phase) {
      PaintBallGamePhase.playing ||
      PaintBallGamePhase.waiting ||
      PaintBallGamePhase.shotAnimating => 'paintBallBattle',
      PaintBallGamePhase.knockout => 'paintBallKnockout',
      _ => null,
    };
    if (route == null) return;

    _routing = true;
    final action = await context.pushNamed<PaintBallExitAction>(
      route,
      pathParameters: {'sessionId': sessionId},
    );
    if (!mounted) return;
    _routing = false;

    if (action == PaintBallExitAction.playAgain) {
      ref.read(paintBallSessionProvider.notifier).reset();
      return;
    }
    Navigator.of(context).pop(action ?? PaintBallExitAction.backToChat);
  }
}
