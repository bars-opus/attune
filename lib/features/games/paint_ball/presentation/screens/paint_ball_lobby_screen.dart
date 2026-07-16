// lib/features/games/paint_ball/presentation/screens/paint_ball_lobby_screen.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/exports/export_screens.dart';
import '../../models/paint_ball_models.dart';
import '../state/paint_ball_provider.dart';
import 'paint_ball_battle_screen.dart';
import 'paint_ball_knockout_screen.dart';

class PaintBallLobbyScreen extends ConsumerStatefulWidget {
  final String relationshipId;

  const PaintBallLobbyScreen({
    super.key,
    required this.relationshipId,
  });

  @override
  ConsumerState<PaintBallLobbyScreen> createState() =>
      _PaintBallLobbyScreenState();
}

class _PaintBallLobbyScreenState extends ConsumerState<PaintBallLobbyScreen> {
  String _selectedTone = 'playful';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(paintBallSessionProvider);
      final session = state.session;
      if (session != null && session.relationshipId == widget.relationshipId) {
        _routeForPhase(state.phase, session.sessionId);
        return;
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
    ref.listen<PaintBallGamePhase>(paintBallGamePhaseProvider, (previous, next) {
      final sessionId = ref.read(paintBallCurrentSessionProvider)?.sessionId;
      if (sessionId != null) {
        _routeForPhase(next, sessionId);
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
    final isIncomingInvite = session != null &&
        session.relationshipId == widget.relationshipId &&
        session.isInvited &&
        currentUserId != null &&
        session.initiatorId != currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paint Ball'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paint Ball',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'Playful pressure · 3 lives each',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.xl.h),
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
                    'Tap to fire when the moving marker feels right. Each hit removes one life. Lose all 3 lives and the game flips into a free Truth or Dare prompt.',
                    style: textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  Gap(Spacing.md.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFeature('3', 'Lives', colorScheme),
                      _buildFeature('↔', 'Timing', colorScheme),
                      _buildFeature('T/D', 'Penalty', colorScheme),
                    ],
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),
            Text(
              'Choose your tone',
              style: textTheme.titleMedium,
            ),
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
            Gap(Spacing.lg.h),
            if (session != null && session.relationshipId == widget.relationshipId) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.08),
                  ),
                ),
                child: Text(
                  session.isInvited
                      ? 'Waiting for your partner to accept.'
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
                      onPressed: () =>
                          notifier.declineSession(session.sessionId),
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                    ),
                  ),
                  Gap(Spacing.md.w),
                  Expanded(
                    child: AppButton(
                      label: 'Accept',
                      onPressed: () =>
                          notifier.acceptSession(session.sessionId),
                      size: ButtonSize.small,
                    ),
                  ),
                ],
              )
            else
              AppButton(
                label: session == null ? 'Start Game' : 'Resume Game',
                onPressed: () async {
                  if (session != null) {
                    _routeForPhase(state.phase, session.sessionId);
                    return;
                  }
                  await notifier.createSession(
                    relationshipId: widget.relationshipId,
                    tone: _selectedTone,
                  );
                },
                size: ButtonSize.small,
                width: double.infinity,
              ),
            Gap(Spacing.sm.h),
            if (state.errorMessage != null)
              Text(
                state.errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
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

  void _routeForPhase(PaintBallGamePhase phase, String sessionId) {
    if (!mounted) return;
    if (phase == PaintBallGamePhase.playing) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaintBallBattleScreen(sessionId: sessionId),
        ),
      );
      return;
    }
    if (phase == PaintBallGamePhase.knockout) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaintBallKnockoutScreen(sessionId: sessionId),
        ),
      );
    }
  }
}
