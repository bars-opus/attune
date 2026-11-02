import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/me/data/me_device_store.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// J1 (Spec 1 §3.10): "Start here" until the first note or first quiz; once,
/// after the first note, "Saved, just for you." (the Just-for-me
/// celebration: the check fades in over 150 ms, text only).
class FirstActionCard extends ConsumerStatefulWidget {
  const FirstActionCard({super.key});

  @override
  ConsumerState<FirstActionCard> createState() => _FirstActionCardState();
}

class _FirstActionCardState extends ConsumerState<FirstActionCard> {
  /// The celebration was decided this visit: it stays until the person
  /// leaves, though the phone already counts it as shown.
  bool _celebrating = false;

  MeDeviceStore? _store() {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return null;
    return MeDeviceStore(ref.read(sharedPreferencesProvider), userId: userId);
  }

  void _record(FirstActionStage stage) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _store()?.setFirstAction(stage);
    });
  }

  @override
  Widget build(BuildContext context) {
    final inputs = ref.watch(firstActionInputsProvider);
    final store = _store();
    final hasNote = inputs.hasNote;
    final hasQuiz = inputs.hasQuiz;
    if (store == null || hasNote == null || hasQuiz == null) {
      return const SizedBox.shrink();
    }
    final stage = store.firstAction;
    if (!hasNote && !hasQuiz) {
      if (stage == FirstActionStage.none) _record(FirstActionStage.started);
      return const _StartHere();
    }
    if (_celebrating || (hasNote && stage == FirstActionStage.started)) {
      if (!_celebrating) {
        _celebrating = true;
        _record(FirstActionStage.celebrated);
      }
      return const _SavedForYou();
    }
    if (stage != FirstActionStage.celebrated) {
      _record(FirstActionStage.celebrated);
    }
    return const SizedBox.shrink();
  }
}

class _StartHere extends StatelessWidget {
  const _StartHere();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.flow_firstStartHere,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SpaceRow(
                title: loc.flow_firstWriteNote,
                subtitle: '',
                icon: Icons.edit_note_outlined,
                onTap: () => context.pushNamed('reflectionJournal'),
              ),
              SpaceRow(
                title: loc.flow_firstQuiz,
                subtitle: '',
                icon: Icons.psychology_outlined,
                onTap:
                    () => context.pushNamed('quizEntry', extra: 'attachment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedForYou extends StatelessWidget {
  const _SavedForYou();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final duration =
        reduceMotionOf(context) ? Duration.zero : kSelectionDuration;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: duration,
              builder:
                  (_, opacity, child) =>
                      Opacity(opacity: opacity, child: child),
              child: Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                loc.flow_firstSaved,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
