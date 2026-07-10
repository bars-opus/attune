import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/custom_truth_or_dare_list_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_history_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_session_router_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_tone_selector_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TruthOrDareGameScreen extends ConsumerWidget {
  const TruthOrDareGameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeSessionAsync = ref.watch(activeTruthOrDareSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Truth or Dare')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SemanticContainerWidget(
              title: 'Truth or Dare',
              content:
                  'This game uses alternating turns, random truth-or-dare selection, private skip handling, and a lightweight safety check for truth answers.',
              icon: Icons.casino_outlined,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
              borderColor: colorScheme.primary,
              iconColor: colorScheme.primary,
              textTheme: textTheme,
            ),
            Gap(Spacing.lg.h),
            activeSessionAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (session) {
                if (session == null) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(bottom: Spacing.md.h),
                  child: AppButton(
                    label:
                        session.status == 'invited'
                            ? 'Open invitation'
                            : 'Resume active game',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => TruthOrDareSessionRouterScreen(
                                sessionId: session.id,
                              ),
                        ),
                      );
                    },
                    width: double.infinity,
                    size: ButtonSize.large,
                  ),
                );
              },
            ),
            AppButton(
              label: 'Start new game',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TruthOrDareToneSelectorScreen(),
                  ),
                );
              },
              width: double.infinity,
              size: ButtonSize.large,
            ),
            Gap(Spacing.md.h),
            AppButton(
              label: 'Custom questions',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CustomTruthOrDareListScreen(),
                  ),
                );
              },
              width: double.infinity,
              size: ButtonSize.large,
            ),
            Gap(Spacing.md.h),
            AppButton(
              label: 'Past sessions',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TruthOrDareHistoryScreen(),
                  ),
                );
              },
              width: double.infinity,
              size: ButtonSize.large,
              customColor: colorScheme.surfaceContainerHighest,
              textColor: colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}
