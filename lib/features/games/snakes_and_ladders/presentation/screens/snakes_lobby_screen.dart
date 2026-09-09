import 'dart:async';
import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/screens/snakes_game_screen.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/state/snakes_provider.dart';
import 'package:attune/features/games/snakes_and_ladders/presentation/widgets/snakes_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Where a game is started or joined.
///
/// Deliberately plain. This game exists for a couple who want to stop
/// talking for a bit, and a lobby that explained itself at length would
/// be asking for exactly the attention they came here to put down.
class SnakesLobbyScreen extends ConsumerStatefulWidget {
  const SnakesLobbyScreen({
    super.key,
    required this.relationshipId,
    this.acceptSessionId,
  });

  final String relationshipId;

  /// An invitation to accept on arrival, from a tap on the partner's chat
  /// card. The lobby joins and opens the board without rendering itself,
  /// so the tap goes straight from the conversation to the game.
  final String? acceptSessionId;

  @override
  ConsumerState<SnakesLobbyScreen> createState() => _SnakesLobbyScreenState();
}

class _SnakesLobbyScreenState extends ConsumerState<SnakesLobbyScreen> {
  SnakesSession? _existing;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final accept = widget.acceptSessionId;
      if (accept != null) {
        unawaited(_join(accept));
      } else {
        unawaited(_refresh());
      }
    });
  }

  Future<void> _refresh() async {
    final notifier = ref.read(snakesProvider.notifier)..clearError();
    final session = await notifier.findActive(widget.relationshipId);
    if (!mounted) return;
    setState(() {
      _existing = session;
      _loading = false;
      _error = ref.read(snakesProvider).errorMessage;
    });
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final sessionId = await ref
        .read(snakesProvider.notifier)
        .createSession(widget.relationshipId);

    if (!mounted) return;
    if (sessionId == null) {
      setState(() {
        _busy = false;
        _error =
            ref.read(snakesProvider).errorMessage ?? 'Could not start a game.';
      });
      return;
    }
    // Straight back to the chat. The invitation IS the chat card -- the
    // database trigger posts it the moment the session row lands -- so
    // the conversation already shows the game by the time this pops.
    //
    // The lobby used to stay put and show "Waiting for your partner"
    // over a "Back to chat" button, which is a screen whose only purpose
    // is to be left. Tapping your own unaccepted card is where you go to
    // cancel it (see the build method), so nothing is lost.
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Opens the board, and offers a rematch if they asked for one on the
  /// way out. Creating the next game here rather than on the end screen
  /// keeps session creation in one place.
  Future<void> _openGame(String sessionId) async {
    final action = await context.pushNamed<SnakesExitAction>(
      'snakesGame',
      pathParameters: {'sessionId': sessionId},
    );
    if (!mounted) return;
    await _refresh();
    if (action == SnakesExitAction.playAgain && mounted) {
      await _start();
    }
  }

  Future<void> _join(String sessionId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await ref.read(snakesProvider.notifier).acceptSession(sessionId);

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // Arriving by auto-accept means this screen was never meant to be
      // seen -- but a failed join is exactly when it has something to
      // say, so it stays and shows why rather than popping silently.
      setState(
        () =>
            _error =
                ref.read(snakesProvider).errorMessage ??
                'Could not join this game.',
      );
      await _refresh();
      return;
    }
    await _openGame(sessionId);
  }

  Future<void> _decline(String sessionId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(snakesProvider.notifier)
        .declineSession(sessionId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Back to the chat: the invitation is gone, so is the reason to be
      // on this screen. Refreshing in place would leave the player on a
      // lobby offering to start the game they just cancelled.
      if (mounted) Navigator.of(context).maybePop();
    } else {
      setState(
        () =>
            _error =
                ref.read(snakesProvider).errorMessage ??
                'Could not decline this game.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final userId = ref.watch(snakesCurrentUserIdProvider);
    final existing = _existing;

    return Scaffold(
      backgroundColor: SnakesPalette.field,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Snakes and Ladders'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child:
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'No talking required.',
                        style: textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Roll a die, climb a ladder, dodge a snake. '
                        'Take your turns whenever you like.',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 36),
                      if (existing == null)
                        _action('Start a game', _start)
                      else if (existing.isActive)
                        _action('Carry on', () => _openGame(existing.sessionId))
                      else if (existing.isInitiator(userId))
                        // Reached by tapping your own unaccepted card.
                        // The useful thing here is cancelling, not a
                        // button that says "back" -- the system back
                        // gesture already does that.
                        Column(
                          children: [
                            Text(
                              'Waiting for your partner',
                              style: textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _secondaryAction(
                              'Cancel invitation',
                              () => _decline(existing.sessionId),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _action(
                              'Join the game',
                              () => _join(existing.sessionId),
                            ),
                            const SizedBox(height: 12),
                            _secondaryAction(
                              'Decline',
                              () => _decline(existing.sessionId),
                            ),
                          ],
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: SnakesPalette.them,
                          ),
                        ),
                      ],
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: SnakesPalette.you,
        foregroundColor: SnakesPalette.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child:
          _busy
              ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
              : Text(label),
    ),
  );

  Widget _secondaryAction(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    height: 48,
    child: OutlinedButton(
      onPressed: _busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label),
    ),
  );
}
