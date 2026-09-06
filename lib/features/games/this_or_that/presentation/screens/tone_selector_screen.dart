import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
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

  static const _tones = <_ToneOption>[
    _ToneOption(
      id: 'connecting',
      label: 'Connecting',
      description: 'Easy questions that bring you closer',
      icon: Icons.people_alt_rounded,
      color: Color(0xFF3F66D4),
    ),
    _ToneOption(
      id: 'romantic',
      label: 'Romantic',
      description: 'Soft, affectionate, and a little dreamy',
      icon: Icons.favorite_rounded,
      color: Color(0xFFD94C65),
    ),
    _ToneOption(
      id: 'playful',
      label: 'Playful',
      description: 'Silly choices and surprising debates',
      icon: Icons.celebration_rounded,
      color: Color(0xFFF09A36),
    ),
    _ToneOption(
      id: 'spicy',
      label: 'Spicy',
      description: 'Flirty choices with extra heat',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFE35843),
    ),
    _ToneOption(
      id: 'intimate',
      label: 'Intimate',
      description: 'Deeper adult questions, with consent',
      icon: Icons.nights_stay_rounded,
      color: Color(0xFF7957C8),
    ),
  ];

  _ToneOption get _selected =>
      _tones.firstWhere((tone) => tone.id == _selectedTone);

  void _selectTone(_ToneOption tone) {
    if (_selectedTone == tone.id) return;
    ref.read(hapticsProvider).selection();
    ref.read(soundServiceProvider).play(AppSound.gameTap);
    setState(() => _selectedTone = tone.id);
  }

  Future<void> _startGame() async {
    if (_isStarting) return;
    final messenger = ScaffoldMessenger.of(context);
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    if (relationshipId == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('This game unlocks when a relationship is active.'),
        ),
      );
      return;
    }

    if (_selectedTone == 'intimate') {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              icon: const Icon(Icons.favorite_outline_rounded),
              title: const Text('Choose Intimate together'),
              content: const Text(
                'This tone includes adult questions for committed couples. Your partner will also be asked before the game begins.',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isStarting = true);
    try {
      final session = await ref.read(
        createThisOrThatSessionProvider((
          relationshipId: relationshipId,
          tone: _selectedTone,
        )).future,
      );
      if (!mounted) return;
      context.pushReplacementNamed(
        'thisOrThatSessionRouter',
        extra: session.id,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('The game could not start. Try again.')),
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
                  for (final tone in _tones)
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

  final _ToneOption tone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${tone.label}. ${tone.description}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 148,
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
                        duration: const Duration(milliseconds: 180),
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

class _ToneOption {
  const _ToneOption({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
}
