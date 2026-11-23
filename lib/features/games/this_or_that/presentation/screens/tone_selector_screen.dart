import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/domain/this_or_that_tones.dart';
import 'package:attune/features/games/this_or_that/presentation/start_this_or_that.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ToneSelectorScreen extends ConsumerStatefulWidget {
  const ToneSelectorScreen({super.key});

  @override
  ConsumerState<ToneSelectorScreen> createState() => _ToneSelectorScreenState();
}

class _ToneSelectorScreenState extends ConsumerState<ToneSelectorScreen> {
  String _selectedTone = 'connecting';
  bool _isStarting = false;

  ThisOrThatTone get _selected =>
      thisOrThatTones.firstWhere((tone) => tone.id == _selectedTone);

  void _selectTone(ThisOrThatTone tone) {
    if (_selectedTone == tone.id) return;
    ref.read(hapticsProvider).selection();
    ref.read(soundServiceProvider).play(AppSound.gameTap);
    setState(() => _selectedTone = tone.id);
  }

  Future<void> _startGame() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      final sessionId = await startThisOrThat(
        context,
        ref,
        tone: _selectedTone,
      );
      if (sessionId == null || !mounted) return;
      context.pushReplacementNamed(
        'thisOrThatSessionRouter',
        extra: sessionId,
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      title: 'Choose a mood',
      scrollable: true,
      bottom: ThisOrThatPrimaryAction(
        label: 'Play ${_selected.label}',
        onPressed: _startGame,
        loading: _isStarting,
        icon: Icons.play_arrow_rounded,
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          const GameIcon(gameType: 'this_or_that', size: 86),
          const SizedBox(height: 14),
          Text(
            'What kind of game are you in the mood for?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ten private picks. One shared reveal at a time.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tone in thisOrThatTones)
                    SizedBox(
                      width: width,
                      child: _ToneCard(
                        tone: tone,
                        selected: tone.id == _selectedTone,
                        onTap: () => _selectTone(tone),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ToneCard extends StatelessWidget {
  const _ToneCard({
    required this.tone,
    required this.selected,
    required this.onTap,
  });

  final ThisOrThatTone tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final duration =
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: selected,
      label: '${tone.label}. ${tone.description}',
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        height: 156,
        decoration: BoxDecoration(
          color:
              selected
                  ? tone.color.withValues(alpha: 0.14)
                  : palette.panel.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? tone.color : palette.line,
            width: selected ? 2.2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: tone.color.withValues(alpha: selected ? 0.18 : 0.04),
              blurRadius: selected ? 18 : 7,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: tone.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(tone.icon, color: tone.color, size: 21),
                      ),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: duration,
                        child:
                            selected
                                ? Icon(
                                  Icons.check_circle_rounded,
                                  key: const ValueKey('selected'),
                                  color: tone.color,
                                  size: 22,
                                )
                                : const SizedBox.square(
                                  key: ValueKey('unselected'),
                                  dimension: 22,
                                ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    tone.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tone.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.mutedInk,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
