// Spec 2 §3.2 D11 (Step 10 of 12): the verification flow (W4a, §3.3).
// Both checks passed: D12 (or back to where it was opened, R-40). "Change
// that photo" opens D9.
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/verify/verify_flow.dart';
import 'package:flutter/material.dart';

class DatingVerifyStep extends StatelessWidget {
  const DatingVerifyStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  Widget build(BuildContext context) => DatingVerifyFlow(
    step: 'verify',
    onBack: nav.back,
    onDone: () => nav.next('preview'),
    onChangePhotos:
        () => nav.next(nav.from == null ? 'photos' : 'photos?from=${nav.from}'),
  );
}
