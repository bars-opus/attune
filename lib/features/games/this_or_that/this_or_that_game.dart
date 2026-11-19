import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/games/platform/feel/game_tile.dart';
import 'package:attune/features/games/platform/game_definition.dart';
import 'package:attune/features/games/platform/game_landing_state.dart';
import 'package:attune/features/games/platform/game_session_status.dart';
import 'package:attune/features/games/platform/game_strings.dart';
import 'package:attune/features/games/platform/game_theme.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    hide
        currentRelationshipIdProvider,
        currentUserIdProvider,
        supabaseClientProvider;
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/domain/this_or_that_tones.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/start_this_or_that.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// This or That's colour, on every screen of it.
const GameTheme thisOrThatTheme = GameTheme(primary: GameColors.thisOrThat);

/// This or That, as the hub and its landing page know it.
final GameDefinition thisOrThatGame = GameDefinition(
  gameType: 'this_or_that',
  title: gameTypeDisplayName('this_or_that'),
  collectionLabel: 'Quick play',
  tagline: 'Quick choices, shared reveals',
  theme: thisOrThatTheme,
  icon: gameGlyphFor('this_or_that'),
  heroBuilder: (context, theme) => const _ThisOrThatHero(),
  howToPlay: const [
    'Pull THIS or THAT forward to choose, then lock it in.',
    'Your pick stays hidden until your partner has answered too.',
    'When you have both picked, the two answers turn over together.',
    'There are no wrong answers.',
  ],
  controller: const ThisOrThatController(),
);

/// Reads the couple's This or That game and gets a player into it.
class ThisOrThatController extends GameController {
  const ThisOrThatController();

  @override
  GameLandingState watchLanding(WidgetRef ref) {
    // The session is fetched once; a session event (the partner inviting,
    // answering or finishing) fetches it again.
    ref.listen<AsyncValue<void>>(gameSessionEventsProvider, (_, next) {
      if (next.hasValue) ref.invalidate(activeThisOrThatSessionProvider);
    });

    final active = ref.watch(activeThisOrThatSessionProvider);
    // Kept through a refetch, so the page does not flash back to loading.
    if (!active.hasValue) {
      // A failed read is a fresh start, not a dead button: the game's own
      // screens resume a session that is already open.
      return GameLandingState(
        status:
            active.hasError
                ? GameLandingStatus.fresh
                : GameLandingStatus.loading,
      );
    }

    final session = active.value;
    if (session == null) {
      // Newest first: the couple's last game was This or That.
      final recent = ref.watch(recentGamesProvider).valueOrNull;
      final lastWasThis =
          recent != null &&
          recent.isNotEmpty &&
          recent.first['game_type'] == 'this_or_that';
      return GameLandingState(
        status:
            lastWasThis ? GameLandingStatus.finished : GameLandingStatus.fresh,
      );
    }

    final live = watchSessionLanding(
      ref,
      sessionId: session.id,
      initiatorId: session.initiatorId,
    );
    final total = session.totalRounds;
    return GameLandingState(
      status: live.status,
      sessionId: live.sessionId,
      partnerName: live.partnerName,
      caption:
          total > 0
              ? GameStrings.roundOf(session.currentRound.clamp(1, total), total)
              : live.caption,
      // Only a game under way has a round to nudge about: an invitation
      // the partner has not accepted is waiting too.
      canRemind:
          live.status == GameLandingStatus.waiting &&
          session.status == 'active' &&
          _canRemind(ref, session),
    );
  }

  /// Whether the waiting screen would offer a nudge right now.
  bool _canRemind(WidgetRef ref, ThisOrThatSession session) {
    final viewerId = ref.watch(currentUserIdProvider);
    final members =
        ref
            .watch(relationshipMembersProvider(session.relationshipId))
            .valueOrNull;
    final rounds = ref.watch(sessionRoundsProvider(session.id)).valueOrNull;
    if (viewerId == null || members == null || rounds == null) return false;
    return thisOrThatCanRemind(
      rounds: rounds,
      viewerIsPartnerA: viewerId == members.userA,
      now: DateTime.now(),
    );
  }

  @override
  void onResume(WidgetRef ref) {
    // A game started, played or finished from the screens this page opened
    // may not have sent an event: fetch where it stands again.
    ref.invalidate(activeThisOrThatSessionProvider);
    ref.invalidate(recentGamesProvider);
  }

  @override
  Future<void> onPrimary(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) async {
    // The status decides, never the id: a fresh or finished state can carry
    // the id of a session that is over, and Play or Play again must start a
    // new game rather than reopen the old one.
    switch (state.status) {
      case GameLandingStatus.fresh:
      case GameLandingStatus.finished:
        await _startAndOpen(context, ref, tone: 'connecting');
      case GameLandingStatus.invited:
      case GameLandingStatus.yourTurn:
      case GameLandingStatus.waiting:
        final sessionId = state.sessionId;
        if (sessionId == null) return;
        await openSession(context, ref, sessionId: sessionId);
      case GameLandingStatus.loading:
      case GameLandingStatus.comingSoon:
        return;
    }
  }

  @override
  Future<void> onRemind(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = state.partnerName?.trim();
    final partnerName = name == null || name.isEmpty ? 'your partner' : name;
    try {
      ref.invalidate(sendReminderProvider(sessionId));
      await ref.read(sendReminderProvider(sessionId).future);
      ref.read(hapticsProvider).light();
      messenger.showSnackBar(
        SnackBar(content: Text('A gentle nudge was sent to $partnerName.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The reminder could not be sent yet.')),
      );
    }
  }

  @override
  List<GameEntry> entries(
    BuildContext context,
    WidgetRef ref,
    GameLandingState state,
  ) {
    final inProgress = switch (state.status) {
      GameLandingStatus.invited ||
      GameLandingStatus.yourTurn ||
      GameLandingStatus.waiting => true,
      _ => false,
    };
    return [
      // A new game cannot start while one is under way.
      if (!inProgress)
        for (final tone in thisOrThatTones)
          GameEntry(
            title: tone.label,
            subtitle: tone.description,
            onTap:
                (rowContext) => _startAndOpen(rowContext, ref, tone: tone.id),
          ),
      GameEntry(
        title: 'Your questions',
        onTap:
            (rowContext) =>
                unawaited(rowContext.pushNamed('thisOrThatCustomList')),
      ),
      GameEntry(
        title: 'Past games',
        onTap:
            (rowContext) =>
                unawaited(rowContext.pushNamed('thisOrThatSessionHistory')),
      ),
      GameEntry(
        title: 'From the community',
        onTap:
            (rowContext) => unawaited(
              rowContext.pushNamed(
                'communityFeed',
                queryParameters: const {'type': 'This or That'},
              ),
            ),
      ),
    ];
  }

  @override
  Future<void> openSession(
    BuildContext context,
    WidgetRef ref, {
    required String sessionId,
  }) async {
    // Not awaited: the push lasts until the game is closed, and the page
    // hears the player is back through onResume.
    unawaited(context.pushNamed('thisOrThatSessionRouter', extra: sessionId));
  }

  /// Starts a game in [tone] and opens it, unless it did not start.
  Future<void> _startAndOpen(
    BuildContext context,
    WidgetRef ref, {
    required String tone,
  }) async {
    final sessionId = await startThisOrThat(context, ref, tone: tone);
    if (sessionId == null || !context.mounted) return;
    await openSession(context, ref, sessionId: sessionId);
  }
}

/// THIS and THAT, side by side, with a small "or" between.
class _ThisOrThatHero extends StatelessWidget {
  const _ThisOrThatHero();

  static const Color _thisColor = Color(0xFFFF8A76);
  static const Color _thatColor = Color(0xFF8DA7FF);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'THIS or THAT',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _word('THIS', _thisColor),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(
                  color: GameTheme.onGround,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _word('THAT', _thatColor),
          ],
        ),
      ),
    );
  }

  static Widget _word(String word, Color color) {
    return GameTile(
      radius: 16,
      depth: 6,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Text(
        word,
        style: TextStyle(
          color: color,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
