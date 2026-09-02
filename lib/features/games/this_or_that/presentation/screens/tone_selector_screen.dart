import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/this_or_that_session_router_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ToneSelectorScreen extends ConsumerStatefulWidget {
  const ToneSelectorScreen({super.key});

  @override
  ConsumerState<ToneSelectorScreen> createState() => _ToneSelectorScreenState();
}

class _ToneSelectorScreenState extends ConsumerState<ToneSelectorScreen> {
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
        createThisOrThatSessionProvider((
          relationshipId: relationshipId,
          tone: _selectedTone,
        )).future,
      );
      if (!mounted) return;
      // Same page-based route problem as Truth or Dare: an imperative
      // pushReplacement on a GoRouter page throws, and the failure landed
      // in the catch below as "Could not start the game right now."
      context.pushReplacementNamed(
        'thisOrThatSessionRouter',
        extra: session.id,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the game right now.')),
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Set the tone')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                itemCount: _tones.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: Spacing.md.h,
                  crossAxisSpacing: Spacing.md.w,
                  childAspectRatio: 1.25,
                ),
                itemBuilder: (context, index) {
                  final tone = _tones[index];
                  final isSelected = _selectedTone == tone.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTone = tone.$1),
                    child: Container(
                      padding: EdgeInsets.all(Spacing.md.w),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? colorScheme.primary.withValues(alpha: 0.1)
                                : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.md.r,
                        ),
                        border: Border.all(
                          color:
                              isSelected
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.2),
                          width: isSelected ? BorderWidthTokens.thick : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(tone.$3, style: textTheme.headlineSmall),
                          Gap(Spacing.md.h),
                          Text(
                            tone.$2,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Gap(Spacing.md.h),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Selected: ${_tones.firstWhere((tone) => tone.$1 == _selectedTone).$2}',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            Gap(Spacing.md.h),
            AppButton(
              label: 'Start game',
              onPressed: _startGame,
              isLoading: _isStarting,
              width: double.infinity,
              size: ButtonSize.large,
            ),
          ],
        ),
      ),
    );
  }
}
