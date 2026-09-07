import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class QuestionSourceScreen extends ConsumerStatefulWidget {
  const QuestionSourceScreen({
    super.key,
    required this.sessionId,
    required this.nextRound,
    required this.totalRounds,
    required this.isChooser,
    required this.chooserName,
    required this.currentUserId,
    required this.partnerUserId,
    required this.partnerName,
  });

  final String sessionId;
  final int nextRound;
  final int totalRounds;
  final bool isChooser;
  final String chooserName;
  final String currentUserId;
  final String partnerUserId;
  final String partnerName;

  @override
  ConsumerState<QuestionSourceScreen> createState() =>
      _QuestionSourceScreenState();
}

class _QuestionSourceScreenState extends ConsumerState<QuestionSourceScreen> {
  bool _choosingOwner = false;
  bool _busy = false;
  bool _leaving = false;
  String? _selectedKey;
  String? _error;

  Future<void> _choose({required String source, String? ownerId}) async {
    if (_busy) return;
    final selectionKey = ownerId ?? source;
    setState(() {
      _busy = true;
      _selectedKey = selectionKey;
      _error = null;
    });
    ref.read(hapticsProvider).selection();
    ref.read(soundServiceProvider).play(AppSound.gameTap);

    try {
      final request = (
        sessionId: widget.sessionId,
        nextRound: widget.nextRound,
        source: source,
        customOwnerId: ownerId,
      );
      ref.invalidate(chooseNextQuestionProvider(request));
      final fallback = await ref.read(
        chooseNextQuestionProvider(request).future,
      );
      if (!mounted) return;
      Navigator.of(context).pop(fallback);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _selectedKey = null;
        _error = 'The next card could not be prepared. Try once more.';
      });
    }
  }

  void _leaveWhenReady() {
    if (_leaving || !mounted) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isChooser) {
      ref.listen(thisOrThatSessionPulseProvider(widget.sessionId), (_, __) {
        ref.invalidate(sessionProvider(widget.sessionId));
      });
      ref.watch(thisOrThatSessionPulseProvider(widget.sessionId));
      final session = ref.watch(sessionProvider(widget.sessionId)).valueOrNull;
      if (session != null && session.currentRound >= widget.nextRound) {
        _leaveWhenReady();
      }
    }

    return ThisOrThatGameScaffold(
      title: 'Next card',
      roundNumber: widget.nextRound,
      totalRounds: widget.totalRounds,
      child: widget.isChooser ? _buildChooser(context) : _buildWaiting(context),
    );
  }

  Widget _buildChooser(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final duration =
        reduceMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300);
    return Column(
      children: [
        const SizedBox(height: 8),
        ThisOrThatStageLabel(
          text: _choosingOwner ? 'Choose a deck' : 'Your turn to choose',
          icon:
              _choosingOwner
                  ? Icons.people_alt_rounded
                  : Icons.auto_awesome_rounded,
          color: palette.thisColor,
        ),
        const SizedBox(height: 16),
        Text(
          _choosingOwner
              ? 'Whose questions should lead?'
              : 'Where should the next question come from?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _choosingOwner
              ? 'Only questions shared with your relationship can appear.'
              : 'The choice changes this round only. You will alternate next time.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.mutedInk,
            height: 1.4,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 26),
        Expanded(
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child:
                _choosingOwner
                    ? _buildOwnerChoices(palette)
                    : _buildSourceChoices(palette),
          ),
        ),
        AnimatedSize(
          duration: duration,
          child:
              _error == null
                  ? const SizedBox.shrink()
                  : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildSourceChoices(ThisOrThatPalette palette) {
    return Row(
      key: const ValueKey('source-choices'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _SourceCard(
            label: 'Preset deck',
            description: 'A surprise from Attune',
            icon: Icons.casino_rounded,
            color: palette.thisColor,
            selected: _selectedKey == 'preset',
            loading: _busy && _selectedKey == 'preset',
            onTap: _busy ? null : () => _choose(source: 'preset'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SourceCard(
            label: 'Our questions',
            description: 'Something one of you wrote',
            icon: Icons.edit_note_rounded,
            color: palette.thatColor,
            selected: _choosingOwner,
            loading: false,
            onTap: _busy ? null : () => setState(() => _choosingOwner = true),
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerChoices(ThisOrThatPalette palette) {
    return Column(
      key: const ValueKey('owner-choices'),
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _SourceCard(
                  label: 'My deck',
                  description: 'Use one of my shared questions',
                  icon: Icons.person_rounded,
                  color: palette.thisColor,
                  selected: _selectedKey == widget.currentUserId,
                  loading: _busy && _selectedKey == widget.currentUserId,
                  onTap:
                      _busy
                          ? null
                          : () => _choose(
                            source: 'custom',
                            ownerId: widget.currentUserId,
                          ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SourceCard(
                  label: '${widget.partnerName}\'s deck',
                  description: 'Use one of their shared questions',
                  icon: Icons.favorite_rounded,
                  color: palette.thatColor,
                  selected: _selectedKey == widget.partnerUserId,
                  loading: _busy && _selectedKey == widget.partnerUserId,
                  onTap:
                      _busy
                          ? null
                          : () => _choose(
                            source: 'custom',
                            ownerId: widget.partnerUserId,
                          ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed:
              _busy ? null : () => setState(() => _choosingOwner = false),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Choose another source'),
        ),
      ],
    );
  }

  Widget _buildWaiting(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const ThisOrThatWaitingMark(size: 138),
        const SizedBox(height: 22),
        Text(
          '${widget.chooserName} is picking the next deck',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: palette.ink,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Preset or personal? Their choice will appear here for both of you.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.mutedInk,
            height: 1.45,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool selected;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final duration =
        reduceMotionOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $description',
      child: AnimatedScale(
        scale: selected ? 1 : 0.98,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: duration,
          decoration: BoxDecoration(
            color:
                selected
                    ? color.withValues(alpha: 0.14)
                    : palette.panel.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? color : palette.line,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: selected ? 0.18 : 0.06),
                blurRadius: selected ? 22 : 9,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child:
                          loading
                              ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: color,
                                ),
                              )
                              : Icon(icon, color: color, size: 31),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.mutedInk,
                        height: 1.3,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
