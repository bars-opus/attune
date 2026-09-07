import 'package:attune/features/games/snakes_and_ladders/models/snakes_models.dart';
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
  const SnakesLobbyScreen({super.key, required this.relationshipId});

  final String relationshipId;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final session = await ref
        .read(snakesProvider.notifier)
        .findActive(widget.relationshipId);
    if (!mounted) return;
    setState(() {
      _existing = session;
      _loading = false;
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
    setState(() => _busy = false);

    if (sessionId == null) {
      setState(
        () =>
            _error =
                ref.read(snakesProvider).errorMessage ??
                'Could not start a game.',
      );
      return;
    }
    context.pushReplacementNamed(
      'snakesGame',
      pathParameters: {'sessionId': sessionId},
    );
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
      setState(
        () =>
            _error =
                ref.read(snakesProvider).errorMessage ??
                'Could not join this game.',
      );
      return;
    }
    context.pushReplacementNamed(
      'snakesGame',
      pathParameters: {'sessionId': sessionId},
    );
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
                        _action(
                          'Carry on',
                          () => context.pushReplacementNamed(
                            'snakesGame',
                            pathParameters: {'sessionId': existing.sessionId},
                          ),
                        )
                      else if (existing.currentTurnUserId == null &&
                          userId != null &&
                          existing.userA != userId &&
                          existing.userB != userId)
                        const SizedBox.shrink()
                      else
                        _action(
                          'Join the game',
                          () => _join(existing.sessionId),
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
}
