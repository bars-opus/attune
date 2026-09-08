import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/state/word_hunt_provider.dart';
import 'package:attune/features/games/word_hunt/presentation/widgets/word_hunt_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

/// Where a hunt is started or joined.
///
/// Kept plain for the same reason Snakes' lobby is: this is the Arcade,
/// and a couple reaching for it want to stop talking for a minute rather
/// than read a page about a word game.
class WordHuntLobbyScreen extends ConsumerStatefulWidget {
  const WordHuntLobbyScreen({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  ConsumerState<WordHuntLobbyScreen> createState() =>
      _WordHuntLobbyScreenState();
}

class _WordHuntLobbyScreenState extends ConsumerState<WordHuntLobbyScreen> {
  WordHuntSession? _existing;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final session = await ref
          .read(wordHuntGatewayProvider)
          .getActiveSession(widget.relationshipId);
      if (!mounted) return;
      setState(() {
        _existing = session;
        _loading = false;
        _error = null;
      });
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach the game. Check your connection.';
      });
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sessionId = await ref
          .read(wordHuntGatewayProvider)
          .createSession(
            relationshipId: widget.relationshipId,
            idempotencyKey:
                'word_hunt:${widget.relationshipId}:'
                '${const Uuid().v4()}',
          );
      if (!mounted) return;
      // Creating sends an invitation. Both players hunt the same grid, so
      // there is nothing for the inviter to do until it is accepted --
      // opening a board here would start a clock against a partner who
      // has not agreed to play.
      await _refresh();
      if (mounted) setState(() => _busy = false);
      debugPrint('word hunt session $sessionId invited');
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start a hunt. Try again.';
      });
    }
  }

  Future<void> _accept(String sessionId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(wordHuntGatewayProvider).acceptSession(sessionId);
      if (!mounted) return;
      await _open(sessionId);
    } on WordHuntApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  Future<void> _open(String sessionId) async {
    await context.pushNamed(
      'wordHuntGame',
      pathParameters: {'sessionId': sessionId},
    );
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(wordHuntCurrentUserIdProvider);
    final existing = _existing;

    return Scaffold(
      backgroundColor: WordHuntPalette.field,
      appBar: AppBar(
        backgroundColor: WordHuntPalette.field,
        foregroundColor: WordHuntPalette.letter,
        elevation: 0,
        title: const Text('Word Hunt'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child:
              _loading
                  ? const Center(
                    child: CircularProgressIndicator(
                      color: WordHuntPalette.found,
                    ),
                  )
                  : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      const Text(
                        'One hidden word.',
                        style: TextStyle(
                          color: WordHuntPalette.letter,
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You both search the same grid. Drag across the '
                        'letters when you spot it.',
                        style: TextStyle(
                          color: WordHuntPalette.dim,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Says plainly what the clock is, because tapping
                      // Start is what begins it and that must not surprise
                      // anyone.
                      const Text(
                        'Your time starts when you tap Start, not now.',
                        style: TextStyle(
                          color: WordHuntPalette.reveal,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const Spacer(),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFF8A8A),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (existing == null)
                        _PrimaryButton(
                          label: 'Invite them to hunt',
                          busy: _busy,
                          onPressed: _create,
                        )
                      else if (existing.isInvited && existing.initiatorId == me)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Waiting for them to join.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: WordHuntPalette.dim,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _SecondaryButton(
                              label: 'Cancel the invitation',
                              busy: _busy,
                              onPressed: () async {
                                await ref
                                    .read(wordHuntGatewayProvider)
                                    .declineSession(existing.sessionId);
                                await _refresh();
                              },
                            ),
                          ],
                        )
                      else if (existing.isInvited)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PrimaryButton(
                              label: 'Join the hunt',
                              busy: _busy,
                              onPressed: () => _accept(existing.sessionId),
                            ),
                            const SizedBox(height: 12),
                            _SecondaryButton(
                              label: 'Not now',
                              busy: _busy,
                              onPressed: () async {
                                await ref
                                    .read(wordHuntGatewayProvider)
                                    .declineSession(existing.sessionId);
                                await _refresh();
                              },
                            ),
                          ],
                        )
                      else
                        _PrimaryButton(
                          label:
                              existing.hasStarted
                                  ? 'Back to your hunt'
                                  : 'Open the hunt',
                          busy: _busy,
                          onPressed: () => _open(existing.sessionId),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: WordHuntPalette.found,
      foregroundColor: const Color(0xFF04201C),
      disabledBackgroundColor: WordHuntPalette.grid,
      disabledForegroundColor: WordHuntPalette.dim,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child:
        busy
            ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WordHuntPalette.dim,
              ),
            )
            : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
  );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: busy ? null : onPressed,
    style: TextButton.styleFrom(
      foregroundColor: WordHuntPalette.dim,
      minimumSize: const Size.fromHeight(48),
    ),
    child: Text(label, style: const TextStyle(fontSize: 15)),
  );
}
