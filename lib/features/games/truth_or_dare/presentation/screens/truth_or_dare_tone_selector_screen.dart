import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/community/presentation/widgets/community_questions_entry.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_session_router_screen.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/feedback/sound_service.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/games/truth_or_dare/presentation/widgets/truth_or_dare_game_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TruthOrDareToneSelectorScreen extends ConsumerStatefulWidget {
  const TruthOrDareToneSelectorScreen({super.key});

  @override
  ConsumerState<TruthOrDareToneSelectorScreen> createState() =>
      _TruthOrDareToneSelectorScreenState();
}

class _TruthOrDareToneSelectorScreenState
    extends ConsumerState<TruthOrDareToneSelectorScreen> {
  String _selectedTone = 'connecting';
  bool _isStarting = false;

  static const _tones = [
    ('connecting', 'Connecting', '💙'),
    ('romantic', 'Romantic', '❤️'),
    ('playful', 'Playful', '😄'),
    ('spicy', 'Spicy', '🔥'),
    ('intimate', 'Intimate', '🌙'),
  ];

  Future<void> _startGame() async {
    if (_isStarting) return;

    final messenger = ScaffoldMessenger.of(context);
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);

    if (relationshipId == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Games unlock only for an active relationship.'),
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
              title: const Text('Intimate tone'),
              content: const Text(
                'This tone contains adult content intended for committed couples. Your partner will need to confirm before the game starts.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes, set Intimate'),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isStarting = true);
    try {
      final session = await ref.read(
        createTruthOrDareSessionProvider((
          relationshipId: relationshipId,
          tone: _selectedTone,
        )).future,
      );

      if (!mounted) return;
      // pushReplacementNamed, not Navigator.pushReplacement with a
      // MaterialPageRoute: this screen is a GoRouter page-based route, and
      // completing one imperatively throws
      //
      //   'A page-based route cannot be completed using imperative api'
      //
      // The session was already created by then, so the game existed and
      // only the navigation failed -- which surfaced as "Could not start
      // Truth or Dare right now."
      context.pushReplacementNamed(
        'truthOrDareSessionRouter',
        extra: session.id,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not start Truth or Dare right now.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Palette follows the CURRENT selection, so tapping a tone repaints
    // the whole screen in it. The choice is otherwise invisible until the
    // game has already started, which makes it feel like a label rather
    // than a decision.
    final palette = TruthOrDarePalette.of(context, tone: _selectedTone);
    final textTheme = Theme.of(context).textTheme;

    return TruthOrDareScaffold(
      title: 'Set the tone',
      tone: _selectedTone,
      scrollable: true,
      bottom: TruthOrDarePrimaryAction(
        label: 'Start the game',
        icon: Icons.play_arrow_rounded,
        busy: _isStarting,
        onPressed: _isStarting ? null : _startGame,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How light or deep should this one get?',
            style: textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(
            'You can pick a different tone next time.',
            style: textTheme.bodySmall?.copyWith(color: palette.mutedInk),
          ),
          Gap(Spacing.lg.h),
          ..._tones.map((tone) {
            final selected = _selectedTone == tone.$1;
            final accent =
                TruthOrDarePalette.of(context, tone: tone.$1).toneAccent;

            return Padding(
              padding: EdgeInsets.only(bottom: Spacing.sm.h),
              child: Semantics(
                button: true,
                selected: selected,
                label: tone.$2,
                child: GestureDetector(
                  onTap: () {
                    if (_selectedTone == tone.$1) return;
                    setState(() => _selectedTone = tone.$1);
                    ref.read(hapticsProvider).selection();
                    ref.read(soundServiceProvider).play(AppSound.gameTap);
                  },
                  child: AnimatedContainer(
                    duration:
                        reduceMotionOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.all(Spacing.md.w),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? accent.withValues(alpha: 0.12)
                              : palette.panel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? accent : palette.line,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(tone.$3, style: const TextStyle(fontSize: 26)),
                        Gap(Spacing.md.w),
                        Expanded(
                          child: Text(
                            tone.$2,
                            style: textTheme.titleMedium?.copyWith(
                              color: palette.ink,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        AnimatedScale(
                          scale: selected ? 1 : 0,
                          duration:
                              reduceMotionOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: accent,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          Gap(Spacing.lg.h),
          const CommunityQuestionsEntry(typeFilter: 'Truth'),
        ],
      ),
    );
  }
}
