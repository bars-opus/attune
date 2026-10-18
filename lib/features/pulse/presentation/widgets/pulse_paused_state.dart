// lib/features/pulse/presentation/widgets/pulse_paused_state.dart
import 'package:attune/core/utils/exports/export_screens.dart';

/// Pulse while the relationship is paused (F5 (5)): nothing is computed or
/// shown — no score, no check-in, no refresh.
class PulsePausedState extends StatelessWidget {
  const PulsePausedState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(Spacing.lg.w),
      child: const EmptyStateWidget(
        icon: Icons.pause_circle_outline,
        title: 'Pulse is paused',
        subtitle:
            'Nothing is computed or shown while your relationship is paused.',
      ),
    );
  }
}
