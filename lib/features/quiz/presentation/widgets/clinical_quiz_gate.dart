// lib/features/quiz/presentation/widgets/clinical_quiz_gate.dart
//
// Spec 5 (R5-6, plan review I1): the communication and conflict quizzes stay
// registered, but until clinical sign-off (quiz_clinical_signoff) their
// screens say "Coming soon".

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ClinicalQuizGate extends ConsumerWidget {
  const ClinicalQuizGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedOff = ref.watch(quizClinicalSignoffProvider);
    return signedOff.when(
      data: (on) => on ? child : const _ComingSoon(),
      loading:
          () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _ComingSoon(),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Coming soon', style: textTheme.titleLarge),
            Gap(Spacing.sm.h),
            Text(
              'This reflection is being checked by a clinician before it opens.',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
